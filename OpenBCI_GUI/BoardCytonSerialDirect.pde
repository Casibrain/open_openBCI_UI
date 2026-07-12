///////////////////////////////////////////////////////////////////////////////
//
// BoardCytonSerialDirect - Direct USB serial connection to Cyton
// Uses jSerialComm for cross-platform serial communication
// Parses OpenBCI binary packet format directly
// Auto-detects channel count (8 or 16) from packet structure
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

    // Channel config - dynamic, auto-detected from packet structure
    private int numEegChannels = 0; // Will be detected from first complete packet
    private boolean channelsDetected = false;
    private final int NUM_AUX_CHANNELS = 3;
    private final float SAMPLE_RATE = 250.0f;
    private final float ADS1299_Vref = 4.5f;
    private final float ADS1299_gain = 24.0f;
    private final float scale_fac_uVolts_per_count = ADS1299_Vref / ((float)(pow(2, 23) - 1)) / ADS1299_gain * 1000000.0f;
    private final float scale_fac_accel_G_per_count = 0.002f / ((float)pow(2, 4));

    // Packet parsing state - buffer-based approach
    // Packet structure: 1(start) + 1(counter) + N*3(EEG) + 6(AUX) + 1(end) = 9 + N*3
    // Max 128 channels: 9 + 128*3 = 393 bytes; use 512 for safety margin
    private final byte BYTE_START = (byte)0xA0;
    private final byte BYTE_END = (byte)0xC0;
    private final byte BYTE_END_ALT = (byte)0xC1;
    private static final int MAX_PACKET_SIZE = 512;
    private boolean packetInProgress = false;
    private byte[] packetBuffer = new byte[MAX_PACKET_SIZE];
    private int packetBufferLen = 0;

    // Parsed data - sized to maximum (16 channels)
    private double[] parsedEegValues = new double[16];
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
            buffer = new Buffer<double[]>(getTotalChannelCount(), (int)SAMPLE_RATE);
        } else {
            buffer = null;
        }
        smoothData = active;
    }

    public boolean getSmoothingActive() {
        return smoothData;
    }

    // Get detected EEG channel count (default to 8 before auto-detection)
    public int getNumEegChannels() {
        return numEegChannels > 0 ? numEegChannels : 8;
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
            // Set non-blocking timeout (0 = no timeout, read returns immediately)
            serialPort.setComPortTimeouts(0, 0, 0);

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
        // Default to 8 channels before auto-detection
        int count = numEegChannels > 0 ? numEegChannels : 8;
        int[] channels = new int[count];
        for (int i = 0; i < count; i++) channels[i] = i;
        return channels;
    }

    @Override
    public int getTimestampChannel() { return getNumEegChannels() + NUM_AUX_CHANNELS; }

    @Override
    public int getSampleIndexChannel() { return getNumEegChannels() + NUM_AUX_CHANNELS + 1; }

    @Override
    public int getMarkerChannel() { return getNumEegChannels() + NUM_AUX_CHANNELS + 2; }

    @Override
    public int getTotalChannelCount() { return getNumEegChannels() + NUM_AUX_CHANNELS + 3; }

    @Override
    protected double[][] getNewDataInternal() {
        int numSamples;
        double[][] result;

        synchronized (dataLock) {
            numSamples = pendingDataQueue.size();
            if (numSamples == 0) return emptyData;

            int totalChannels = getTotalChannelCount();
            result = new double[totalChannels][numSamples];
            for (int i = 0; i < numSamples; i++) {
                double[] sample = pendingDataQueue.get(i);
                for (int j = 0; j < totalChannels; j++) {
                    result[j][i] = sample[j];
                }
            }
            pendingDataQueue.clear();
        }

        if (!smoothData) return result;

        // Apply smoothing
        int totalChannels = getTotalChannelCount();
        for (int i = 0; i < result[0].length; i++) {
            double[] newEntry = new double[totalChannels];
            for (int j = 0; j < totalChannels; j++) {
                newEntry[j] = result[j][i];
            }
            buffer.addNewEntry(newEntry);
        }

        int numData = buffer.getDataCount();
        if (numData == 0) return emptyData;

        double[][] res = new double[totalChannels][numData];
        for (int i = 0; i < numData; i++) {
            double[] curData = buffer.popFirstEntry();
            for (int j = 0; j < totalChannels; j++) {
                res[j][i] = curData[j];
            }
        }
        return res;
    }

    @Override
    protected void addChannelNamesInternal(String[] channelNames) {
        for (int i = 0; i < numEegChannels; i++) channelNames[i] = "EEG_" + (i + 1);
        for (int i = 0; i < NUM_AUX_CHANNELS; i++) channelNames[numEegChannels + i] = "Aux_" + (i + 1);
        channelNames[numEegChannels + NUM_AUX_CHANNELS] = "Timestamp";
        channelNames[numEegChannels + NUM_AUX_CHANNELS + 1] = "SampleIndex";
        channelNames[numEegChannels + NUM_AUX_CHANNELS + 2] = "Marker";
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
        if (!packetInProgress) {
            // Look for start byte
            if (actbyte == BYTE_START) {
                packetInProgress = true;
                packetBufferLen = 0;
                packetBuffer[packetBufferLen++] = actbyte;
            }
            return;
        }

        // Buffer bytes until end byte or overflow
        if (packetBufferLen < MAX_PACKET_SIZE) {
            packetBuffer[packetBufferLen++] = actbyte;
        }

        // Check for end byte
        if (actbyte == BYTE_END || actbyte == BYTE_END_ALT) {
            processCompletePacket();
        } else if (packetBufferLen >= MAX_PACKET_SIZE) {
            // Packet too large, discard
            packetInProgress = false;
        }
    }

    private void processCompletePacket() {
        packetInProgress = false;
        int totalLen = packetBufferLen;

        // Packet structure: 1(start) + 1(counter) + N*3(EEG) + 6(AUX) + 1(end) = 9 + N*3
        // Valid channel counts: 1-128 (power of 2 preferred: 1,2,4,8,16,32,64,128)
        if (totalLen < 10) return; // Too short: minimum is 1+1+1*3+6+1 = 12

        int eegBytes = totalLen - 9; // Subtract start, counter, AUX(6), end
        if (eegBytes <= 0 || eegBytes % 3 != 0) return; // Invalid size

        int detectedChannels = eegBytes / 3;
        if (detectedChannels < 1 || detectedChannels > 128) return; // Out of range

        // Auto-detect channel count (only once)
        if (!channelsDetected) {
            numEegChannels = detectedChannels;
            channelsDetected = true;
            println("BoardCytonSerialDirect: Auto-detected " + numEegChannels + " EEG channels (" + totalLen + " bytes/packet)");

            // Update global nchan and reinitialize UI
            updateToNChan(numEegChannels);

            // Reinitialize smoothing buffer with correct channel count
            if (smoothData) {
                buffer = new Buffer<double[]>(getTotalChannelCount(), (int)SAMPLE_RATE);
            }
        }

        // Parse EEG data: bytes 2..(2+N*3-1)
        int offset = 2; // Skip start byte + frame number
        for (int ch = 0; ch < numEegChannels; ch++) {
            int rawValue = threeBytesToInt(packetBuffer[offset], packetBuffer[offset + 1], packetBuffer[offset + 2]);
            parsedEegValues[ch] = rawValue * scale_fac_uVolts_per_count;
            offset += 3;
        }

        // Parse AUX data: 3 channels × 2 bytes = 6 bytes
        for (int ch = 0; ch < NUM_AUX_CHANNELS; ch++) {
            short rawValue = twoBytesToShort(packetBuffer[offset], packetBuffer[offset + 1]);
            parsedAuxValues[ch] = rawValue * scale_fac_accel_G_per_count;
            offset += 2;
        }

        packetCount++;
        lastPacketTime = System.currentTimeMillis();

        if (packetCount % 500 == 0) {
            println("BoardCytonSerialDirect: Packets: " + packetCount);
        }

        // Debug: print first few EEG values
        if (packetCount <= 3) {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < numEegChannels; i++) {
                sb.append(String.format("ch%d=%.1f ", i, parsedEegValues[i]));
            }
            println("Packet #" + packetCount + " (" + numEegChannels + "ch): " + sb.toString());
        }

        double timestamp = System.currentTimeMillis() / 1000.0;

        // Build sample: [EEG0..N, Aux0..2, Timestamp, SampleIndex, Marker]
        int totalChannels = getTotalChannelCount();
        double[] sample = new double[totalChannels];
        for (int i = 0; i < numEegChannels; i++) {
            sample[i] = parsedEegValues[i];
        }
        for (int i = 0; i < NUM_AUX_CHANNELS; i++) {
            sample[numEegChannels + i] = parsedAuxValues[i];
        }
        sample[numEegChannels + NUM_AUX_CHANNELS] = timestamp;
        sample[numEegChannels + NUM_AUX_CHANNELS + 1] = packetCount % 256;
        sample[numEegChannels + NUM_AUX_CHANNELS + 2] = 0;

        synchronized (dataLock) {
            pendingDataQueue.add(sample);
        }
    }
};

///////////////////////////////////////////////////////////////////////////////
//
// BoardCytonSerialDirectDaisy - Direct USB serial for 16-channel Cyton+Daisy
// Now uses dynamic channel detection from BoardCytonSerialDirect
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
