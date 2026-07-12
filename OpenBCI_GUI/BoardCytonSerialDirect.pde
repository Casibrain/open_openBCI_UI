///////////////////////////////////////////////////////////////////////////////
//
// BoardCytonSerialDirect - Direct USB serial connection to Cyton
// Uses jSerialComm for cross-platform serial communication
// Parses OpenBCI binary packet format directly
//
///////////////////////////////////////////////////////////////////////////////

class BoardCytonSerialDirect extends Board implements SmoothingCapableBoard {

    public BoardIds getBoardId() {
        return BoardIds.CYTON_BOARD;
    }

    // Serial I/O - using jSerialComm for cross-platform support
    private com.fazecast.jSerialComm.SerialPort serialPort;
    private String portName;
    private final int BAUD_RATE = 921600;

    // Dedicated reader thread + ring buffer
    private Thread readerThread;
    private volatile boolean readerRunning = false;
    private final byte[] ringBuffer = new byte[1048576]; // 1MB ring buffer
    private int ringHead = 0; // write position
    private int ringTail = 0; // read position
    private final Object ringLock = new Object();

    // Channel config
    private final int NUM_EEG_CHANNELS = 8;
    private final int NUM_AUX_CHANNELS = 3;
    private final float SAMPLE_RATE = 250.0f;
    private final float ADS1299_Vref = 4.5f;
    private final float ADS1299_gain = 24.0f;
    private final float scale_fac_uVolts_per_count = ADS1299_Vref / ((float)(pow(2, 23) - 1)) / ADS1299_gain * 1000000.0f;
    private final float scale_fac_accel_G_per_count = 0.002f / ((float)pow(2, 4));

    // Packet parsing state
    private final byte BYTE_START = (byte)0xA0;
    private final byte BYTE_END = (byte)0xC0;
    private int PACKET_readstate = 0;
    private int localByteCounter = 0;
    private int localChannelCounter = 0;
    private byte[] localAdsByteBuffer = {0, 0, 0};
    private byte[] localAccelByteBuffer = {0, 0};
    private int frameNumber = 0;
    private int totalBytesInPacket = 0;

    // Parsed data
    private double[] parsedEegValues = new double[NUM_EEG_CHANNELS];
    private double[] parsedAuxValues = new double[NUM_AUX_CHANNELS];

    // Data buffers - use a queue to hold all parsed packets between frames
    private ArrayList<double[]> pendingDataQueue = new ArrayList<double[]>();
    private int packetCount = 0;
    private long lastPacketTime = 0;

    // Smoothing
    private Buffer<double[]> buffer = null;
    private volatile boolean smoothData;

    // Thread safety
    private final Object dataLock = new Object();
    private volatile boolean streaming = false;

    public BoardCytonSerialDirect(String portName) {
        super();
        this.portName = portName;
        setSmoothingActive(true);
    }

    public synchronized void setSmoothingActive(boolean active) {
        if (smoothData == active) return;
        if (active) {
            buffer = new Buffer<double[]>((int)SAMPLE_RATE);
        } else {
            buffer = null;
        }
        smoothData = active;
    }

    public boolean getSmoothingActive() {
        return smoothData;
    }

    // Ring buffer write (called by reader thread)
    private void ringWrite(byte[] data, int len) {
        synchronized (ringLock) {
            for (int i = 0; i < len; i++) {
                ringBuffer[ringHead] = data[i];
                ringHead = (ringHead + 1) % ringBuffer.length;
                // If buffer full, advance tail (drop oldest data)
                if (ringHead == ringTail) {
                    ringTail = (ringTail + 1) % ringBuffer.length;
                }
            }
        }
    }

    // Ring buffer read one byte (returns -1 if empty)
    private int ringRead() {
        synchronized (ringLock) {
            if (ringHead == ringTail) return -1;
            int b = ringBuffer[ringTail] & 0xFF;
            ringTail = (ringTail + 1) % ringBuffer.length;
            return b;
        }
    }

    // Ring buffer available bytes
    private int ringAvailable() {
        synchronized (ringLock) {
            int avail = ringHead - ringTail;
            if (avail < 0) avail += ringBuffer.length;
            return avail;
        }
    }

    // configureSerialPort is no longer needed - jSerialComm handles port configuration internally
    private void configureSerialPort() throws Exception {
        // jSerialComm sets baud rate, data bits, stop bits, parity via setBaudRate() etc.
        // No external command needed
    }

    @Override
    public boolean initializeInternal() {
        try {
            println("BoardCytonSerialDirect: Opening " + portName + " at " + BAUD_RATE + " baud");

            // Find and open the serial port using jSerialComm
            serialPort = com.fazecast.jSerialComm.SerialPort.getCommPort(portName);
            if (serialPort == null) {
                println("BoardCytonSerialDirect: Port " + portName + " not found");
                return false;
            }

            // Configure port parameters
            serialPort.setBaudRate(BAUD_RATE);
            serialPort.setNumDataBits(8);
            serialPort.setNumStopBits(com.fazecast.jSerialComm.SerialPort.ONE_STOP_BIT);
            serialPort.setParity(com.fazecast.jSerialComm.SerialPort.NO_PARITY);
            serialPort.setComPortTimeouts(com.fazecast.jSerialComm.SerialPort.TIMEOUT_NON_BLOCKING, 0, 0);

            // Open the port
            if (!serialPort.openPort()) {
                println("BoardCytonSerialDirect: Failed to open port " + portName);
                return false;
            }

            println("BoardCytonSerialDirect: Port opened successfully");

            // Flush pending data
            byte[] flushBuffer = new byte[4096];
            int flushed = serialPort.readBytes(flushBuffer, flushBuffer.length);
            println("BoardCytonSerialDirect: Flushed " + flushed + " bytes on init");

            // Start dedicated reader thread
            readerRunning = true;
            readerThread = new Thread(new Runnable() {
                public void run() {
                    byte[] readBuffer = new byte[65536];
                    long totalBytesRead = 0;
                    int readCount = 0;
                    while (readerRunning) {
                        try {
                            int n = serialPort.readBytes(readBuffer, readBuffer.length);
                            if (n > 0) {
                                ringWrite(readBuffer, n);
                                totalBytesRead += n;
                                readCount++;
                                // Debug: print first few reads and periodic status
                                if (readCount <= 5 || readCount % 1000 == 0) {
                                    println("BoardCytonSerialDirect: Read #" + readCount + ", " + n + " bytes, total: " + totalBytesRead);
                                }
                            } else {
                                Thread.sleep(1); // avoid busy spin
                            }
                        } catch (Exception e) {
                            if (readerRunning) {
                                println("BoardCytonSerialDirect: Reader error: " + e.getMessage());
                            }
                            break;
                        }
                    }
                    println("BoardCytonSerialDirect: Reader thread stopped. Total read: " + totalBytesRead + " bytes");
                }
            }, "CytonSerialReader");
            readerThread.setDaemon(true);
            readerThread.start();

            streaming = true;
            println("BoardCytonSerialDirect: Board initialized, reader thread started");
            return true;
        } catch (Exception e) {
            println("BoardCytonSerialDirect: Error initializing: " + e.getMessage());
            e.printStackTrace();
            return false;
        }
    }

    @Override
    public void uninitializeInternal() {
        streaming = false;
        readerRunning = false;
        if (readerThread != null) {
            try { readerThread.join(500); } catch (Exception e) {}
            readerThread = null;
        }
        try {
            if (serialPort != null && serialPort.isOpen()) {
                serialPort.closePort();
            }
        } catch (Exception e) {
            println("BoardCytonSerialDirect: Error closing: " + e.getMessage());
        }
        serialPort = null;
    }

    @Override
    public void updateInternal() {
        if (!streaming) return;

        // Drain ALL available data from ring buffer each frame
        int available = ringAvailable();
        if (available > 0) {
            println("BoardCytonSerialDirect: updateInternal - " + available + " bytes available, packets: " + packetCount);
        }
        while (ringAvailable() > 0) {
            int b = ringRead();
            if (b >= 0) {
                interpretBinaryStream((byte)b);
            } else {
                break;
            }
        }
    }

    @Override
    public void startStreaming() { streaming = true; }

    @Override
    public void stopStreaming() { streaming = false; }

    @Override
    public boolean isConnected() { return serialPort != null && serialPort.isOpen(); }

    @Override
    public boolean isStreaming() { return streaming; }

    @Override
    public int getSampleRate() { return (int)SAMPLE_RATE; }

    @Override
    public int[] getEXGChannels() {
        // Return 0-based indices to match our data array layout
        // processNewData() uses exgChannels[Ichan] to index into the data array
        int[] channels = new int[NUM_EEG_CHANNELS];
        for (int i = 0; i < NUM_EEG_CHANNELS; i++) channels[i] = i;
        return channels;
    }

    @Override
    public int getTimestampChannel() { return NUM_EEG_CHANNELS + NUM_AUX_CHANNELS; }

    @Override
    public int getSampleIndexChannel() { return NUM_EEG_CHANNELS + NUM_AUX_CHANNELS + 1; }

    @Override
    public int getMarkerChannel() { return NUM_EEG_CHANNELS + NUM_AUX_CHANNELS + 2; }

    @Override
    public int getTotalChannelCount() { return NUM_EEG_CHANNELS + NUM_AUX_CHANNELS + 3; }

    @Override
    protected double[][] getNewDataInternal() {
        int numSamples;
        double[][] result;

        synchronized (dataLock) {
            numSamples = pendingDataQueue.size();
            if (numSamples == 0) return emptyData;

            result = new double[getTotalChannelCount()][numSamples];
            for (int i = 0; i < numSamples; i++) {
                double[] sample = pendingDataQueue.get(i);
                for (int j = 0; j < getTotalChannelCount(); j++) {
                    result[j][i] = sample[j];
                }
            }
            pendingDataQueue.clear();
        }

        if (!smoothData) return result;

        // Apply smoothing
        for (int i = 0; i < result[0].length; i++) {
            double[] newEntry = new double[getTotalChannelCount()];
            for (int j = 0; j < getTotalChannelCount(); j++) {
                newEntry[j] = result[j][i];
            }
            buffer.addNewEntry(newEntry);
        }

        int numData = buffer.getDataCount();
        if (numData == 0) return emptyData;

        double[][] res = new double[getTotalChannelCount()][numData];
        for (int i = 0; i < numData; i++) {
            double[] curData = buffer.popFirstEntry();
            for (int j = 0; j < getTotalChannelCount(); j++) {
                res[j][i] = curData[j];
            }
        }
        return res;
    }

    @Override
    protected void addChannelNamesInternal(String[] channelNames) {
        for (int i = 0; i < NUM_EEG_CHANNELS; i++) channelNames[i] = "EEG_" + (i + 1);
        for (int i = 0; i < NUM_AUX_CHANNELS; i++) channelNames[NUM_EEG_CHANNELS + i] = "Aux_" + (i + 1);
        channelNames[NUM_EEG_CHANNELS + NUM_AUX_CHANNELS] = "Timestamp";
        channelNames[NUM_EEG_CHANNELS + NUM_AUX_CHANNELS + 1] = "SampleIndex";
        channelNames[NUM_EEG_CHANNELS + NUM_AUX_CHANNELS + 2] = "Marker";
    }

    @Override
    protected PacketLossTracker setupPacketLossTracker() {
        return new PacketLossTracker(getSampleIndexChannel(), getTimestampChannel(), 0, 255);
    }

    @Override
    public Pair<Boolean, String> sendCommand(String command) {
        if (serialPort != null && serialPort.isOpen()) {
            try {
                byte[] data = command.getBytes();
                serialPort.writeBytes(data, data.length);
                return new ImmutablePair<>(true, "");
            } catch (Exception e) {
                println("BoardCytonSerialDirect: Send error: " + e.getMessage());
            }
        }
        return new ImmutablePair<>(false, "");
    }

    @Override public void insertMarker(double value) {}
    @Override public void insertMarker(int value) {}
    @Override public void setEXGChannelActive(int channelIndex, boolean active) {}
    @Override public boolean isEXGChannelActive(int channelIndex) { return true; }

    private int threeBytesToInt(byte b0, byte b1, byte b2) {
        int val = (b0 & 0xFF) | ((b1 & 0xFF) << 8) | ((b2 & 0xFF) << 16);
        if (val >= 0x800000) val -= 0x1000000;
        return val;
    }

    private short twoBytesToShort(byte b0, byte b1) {
        return (short)((b0 & 0xFF) | ((b1 & 0xFF) << 8));
    }

    private void interpretBinaryStream(byte actbyte) {
        switch (PACKET_readstate) {
            case 0:
                if (actbyte == BYTE_START) {
                    PACKET_readstate++;
                    totalBytesInPacket = 1;
                }
                break;
            case 1:
                frameNumber = actbyte & 0xFF;
                localByteCounter = 0;
                localChannelCounter = 0;
                PACKET_readstate++;
                totalBytesInPacket++;
                break;
            case 2:
                localAdsByteBuffer[localByteCounter] = actbyte;
                localByteCounter++;
                totalBytesInPacket++;
                if (localByteCounter == 3) {
                    int rawValue = threeBytesToInt(localAdsByteBuffer[0], localAdsByteBuffer[1], localAdsByteBuffer[2]);
                    parsedEegValues[localChannelCounter] = rawValue * scale_fac_uVolts_per_count;
                    localChannelCounter++;
                    if (localChannelCounter == NUM_EEG_CHANNELS) {
                        PACKET_readstate++;
                        localByteCounter = 0;
                        localChannelCounter = 0;
                    } else {
                        localByteCounter = 0;
                    }
                }
                break;
            case 3:
                localAccelByteBuffer[localByteCounter] = actbyte;
                localByteCounter++;
                totalBytesInPacket++;
                if (localByteCounter == 2) {
                    short rawValue = twoBytesToShort(localAccelByteBuffer[0], localAccelByteBuffer[1]);
                    parsedAuxValues[localChannelCounter] = rawValue * scale_fac_accel_G_per_count;
                    localByteCounter = 0;
                    localChannelCounter++;
                    if (localChannelCounter == NUM_AUX_CHANNELS) {
                        PACKET_readstate++;
                        localByteCounter = 0;
                        localChannelCounter = 0;
                    }
                }
                break;
            case 4:
                totalBytesInPacket++;
                if (actbyte == BYTE_END || actbyte == (byte)0xC1) {
                    processCompletePacket();
                } else if (totalBytesInPacket > 35) {
                    PACKET_readstate = 0;
                }
                break;
        }
    }

    private void processCompletePacket() {
        packetCount++;
        lastPacketTime = System.currentTimeMillis();
        PACKET_readstate = 0;

        if (packetCount % 500 == 0) {
            println("BoardCytonSerialDirect: Packets: " + packetCount);
        }

        // Debug: print first few EEG values for first 3 packets
        if (packetCount <= 3) {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < NUM_EEG_CHANNELS; i++) {
                sb.append(String.format("ch%d=%.1f ", i, parsedEegValues[i]));
            }
            println("Packet #" + packetCount + ": " + sb.toString());
        }

        double timestamp = System.currentTimeMillis() / 1000.0;

        // Build sample: [EEG0..7, Aux0..2, Timestamp, SampleIndex, Marker]
        double[] sample = new double[getTotalChannelCount()];
        for (int i = 0; i < NUM_EEG_CHANNELS; i++) {
            sample[i] = parsedEegValues[i];
        }
        for (int i = 0; i < NUM_AUX_CHANNELS; i++) {
            sample[NUM_EEG_CHANNELS + i] = parsedAuxValues[i];
        }
        sample[NUM_EEG_CHANNELS + NUM_AUX_CHANNELS] = timestamp;
        sample[NUM_EEG_CHANNELS + NUM_AUX_CHANNELS + 1] = packetCount % 256;
        sample[NUM_EEG_CHANNELS + NUM_AUX_CHANNELS + 2] = 0;

        synchronized (dataLock) {
            pendingDataQueue.add(sample);
        }
    }
};

///////////////////////////////////////////////////////////////////////////////
//
// BoardCytonSerialDirectDaisy - Direct USB serial for 16-channel Cyton+Daisy
//
///////////////////////////////////////////////////////////////////////////////

class BoardCytonSerialDirectDaisy extends BoardCytonSerialDirect {

    public BoardCytonSerialDirectDaisy(String portName) {
        super(portName);
    }

    @Override
    public BoardIds getBoardId() {
        return BoardIds.CYTON_DAISY_BOARD;
    }

    @Override
    protected PacketLossTracker setupPacketLossTracker() {
        return new PacketLossTrackerCytonSerialDaisy(getSampleIndexChannel(), getTimestampChannel());
    }
};
