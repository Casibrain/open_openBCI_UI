///////////////////////////////////////////////////////////////////////////////
//
// BoardCytonSerialDirect - Direct USB serial connection to Cyton
// Uses jSerialComm for cross-platform serial communication
// Parses OpenBCI binary packet format directly
// Auto-detects channel count (8, 16, 32, etc.) from packet structure
//
///////////////////////////////////////////////////////////////////////////////

import java.util.Arrays;

class BoardCytonSerialDirect extends Board implements SmoothingCapableBoard, ImpedanceSettingsBoard, ADS1299SettingsBoard {

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
    private int candidatePacketSize = 0; // Candidate packet size for detection
    private int candidateCount = 0; // Consecutive packets with same size for confirmation
    private static final int CANDIDATE_THRESHOLD = 3; // Require 3 matching packets to confirm
    private boolean preDetectionPhase = false; // suppresses updateToNChan during initializeInternal()
    private final int NUM_AUX_CHANNELS = 9;  // 9-axis: accelerometer + gyroscope + magnetometer
    private final int NUM_MARKER_CHANNELS = 6;
    private final float SAMPLE_RATE = 500.0f;
    private final float ADS1299_Vref = 5.0f;   // new_pro.md: 5V reference
    private final float ADS1299_gain = 24.0f;
    private final float scale_fac_uVolts_per_count = ADS1299_Vref / ((float)(pow(2, 23) - 1)) / ADS1299_gain * 1000000.0f;
    private final float scale_fac_accel_G_per_count = 0.002f / ((float)pow(2, 4));

    // Packet parsing state - state machine with byte counting
    // Packet structure: 1(start) + 1(counter) + N*3(EEG) + 18(AUX) + 6(Marker) + 1(end)
    // = 27 + N*3 bytes.  Valid sizes: 8ch=51, 16ch=75, 32ch=123, etc.
    // NOTE: new_pro.md shows 122 bytes for 32ch — may be a doc rounding issue.
    private final byte BYTE_START = (byte)0xA0;
    private final byte BYTE_END = (byte)0xC0;
    private static final int MAX_PACKET_SIZE = 512;
    private static final int PACKET_HEADER = 2; // start byte + frame number
    private static final int PACKET_FOOTER = 1; // end byte
    private static final int PACKET_AUX_SIZE = 18; // 9-axis × 2 bytes
    private static final int PACKET_MARKER_SIZE = 6;
    private int packetState = 0; // 0=waiting for start, 1=reading body, 2=done
    private int packetPosition = 0; // bytes read in current packet (including start)
    private int expectedPacketSize = 0; // 0 = not yet detected
    private byte[] packetBuffer = new byte[MAX_PACKET_SIZE];
    private int packetBufferLen = 0;

    // Parsed data - sized to maximum (128 channels)
    private double[] parsedEegValues = new double[128];
    private double[] parsedAuxValues = new double[NUM_AUX_CHANNELS];
    private double[] parsedMarkerValues = new double[NUM_MARKER_CHANNELS];

    // Handshake state machine
    // STATE_NOCOM=0, STATE_COMINIT=1, STATE_SYNCWITHHARDWARE=2, STATE_NORMAL=3, STATE_STOPPED=4
    private static final int STATE_NOCOM = 0;
    private static final int STATE_COMINIT = 1;
    private static final int STATE_SYNCWITHHARDWARE = 2;
    private static final int STATE_NORMAL = 3;
    private static final int STATE_STOPPED = 4;
    private int handshakeState = STATE_NOCOM;
    private boolean handshakeComplete = false;

    // EOT ($$$) detection for command acknowledgment
    private final byte[] eotSequence = {(byte)'$', (byte)'$', (byte)'$'};
    private int eotMatchIndex = 0;

    // Impedance state per channel (N and P pins)
    private boolean[] isCheckingImpedanceN;
    private boolean[] isCheckingImpedanceP;
    private volatile boolean impedanceMode = false; // pause ring buffer drain during impedance read
    private char[] channelSelectForSettings = {'1','2','3','4','5','6','7','8','Q','W','E','R','T','Y','U','I',
                                               '1','2','3','4','5','6','7','8','Q','W','E','R','T','Y','U','I'};

    // ADS1299 settings (default: all channels ON, gain X24, normal input)
    private ADS1299Settings currentADS1299Settings;

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
        isCheckingImpedanceN = new boolean[128];
        isCheckingImpedanceP = new boolean[128];
        // Defer ADS1299Settings creation until channel count is known
    }

    // Call after channel detection to initialize settings with correct channel count
    public void initADS1299Settings() {
        currentADS1299Settings = new CytonDefaultSettings(this);
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
            handshakeState = STATE_COMINIT;

            // Flush pending data
            byte[] flushBuffer = new byte[4096];
            serialPort.readBytes(flushBuffer, flushBuffer.length);

            // Start dedicated reader thread
            readerRunning = true;
            readerThread = new Thread(new Runnable() {
                public void run() {
                    byte[] readBuffer = new byte[65536];
                    while (readerRunning) {
                        try {
                            int n = serialPort.readBytes(readBuffer, readBuffer.length);
                            if (n > 0) {
                                ringWrite(readBuffer, n);
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
                }
            }, "CytonSerialReader");
            readerThread.setDaemon(true);
            readerThread.start();

            // === Handshake sequence per new_pro.md protocol ===
            // Step 1: Wait 3000ms for board initialization (STATE_COMINIT)
            println("BoardCytonSerialDirect: Waiting 3s for board initialization...");
            try { Thread.sleep(3000); } catch (Exception e) {}

            // Step 2: Send 'v' to reset hardware, wait for '$$$' (STATE_SYNCWITHHARDWARE)
            println("BoardCytonSerialDirect: Sending 'v' reset command...");
            handshakeState = STATE_SYNCWITHHARDWARE;
            sendCommandRaw("v");

            boolean gotEot = waitForEot(5000);
            if (!gotEot) {
                println("BoardCytonSerialDirect: WARNING - No '$$$' after 'v', board may not be Cyton. Proceeding anyway.");
            } else {
                println("BoardCytonSerialDirect: Got '$$$' — hardware reset confirmed");
            }

            // Step 3: Send 'b' to start data streaming
            println("BoardCytonSerialDirect: Sending 'b' start command...");
            sendCommandRaw("b");
            handshakeState = STATE_NORMAL;

            // Step 4: Pre-detect channel count from incoming packets
            println("BoardCytonSerialDirect: Detecting channel count...");
            preDetectionPhase = true;
            long detectStart = System.currentTimeMillis();
            long detectTimeout = 5000; // 5 seconds max to detect
            while (!channelsDetected && (System.currentTimeMillis() - detectStart) < detectTimeout) {
                while (ringAvailable() > 0) {
                    int b = ringRead();
                    if (b >= 0) {
                        interpretBinaryStream((byte)b);
                    }
                    if (channelsDetected) break;
                }
                if (!channelsDetected) {
                    try { Thread.sleep(5); } catch (Exception e) {}
                }
            }
            if (channelsDetected) {
                println("BoardCytonSerialDirect: Channel detection complete: " + numEegChannels + " channels");
            } else {
                println("BoardCytonSerialDirect: Channel detection timed out, defaulting to 32 channels");
                numEegChannels = 32;
                channelsDetected = true;
                expectedPacketSize = 27 + 32 * 3; // 123 bytes for 32ch
            }
            preDetectionPhase = false;

            // Initialize ADS1299 settings now that channel count is known
            initADS1299Settings();

            return true;
        } catch (Exception e) {
            println("BoardCytonSerialDirect: Error initializing: " + e.getMessage());
            e.printStackTrace();
            return false;
        }
    }

    @Override
    public void uninitializeInternal() {
        // Send 's' to stop data streaming before closing
        if (serialPort != null && serialPort.isOpen()) {
            println("BoardCytonSerialDirect: Sending 's' stop command");
            sendCommandRaw("s");
            try { Thread.sleep(100); } catch (Exception e) {}
        }
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
        // Skip ring buffer drain during impedance read to avoid data race
        if (impedanceMode) return;
        // Always drain ring buffer to prevent overflow, regardless of streaming state
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
    public void startStreaming() {
        super.startStreaming();
        streaming = true;
    }

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

    // Standard 10-20 system electrode names for 32 channels
    private final String[] ELEC_NAMES_32 = {
        "Fp1", "Fp2", "AF3", "AF4",
        "F7", "F3", "Fz", "F4", "F8",
        "FC5", "FC1", "FC2", "FC6",
        "T7", "C3", "Cz", "C4", "T8",
        "CP5", "CP1", "CP2", "CP6",
        "P7", "P3", "Pz", "P4", "P8",
        "PO3", "POz", "PO4",
        "O1", "O2"
    };

    @Override
    protected void addChannelNamesInternal(String[] channelNames) {
        for (int i = 0; i < numEegChannels; i++) {
            channelNames[i] = (i < ELEC_NAMES_32.length) ? ELEC_NAMES_32[i] : "EEG_" + (i + 1);
        }
        // 9-axis AUX names: Accel XYZ, Gyro XYZ, Mag XYZ
        String[] auxNames = {"Accel_X", "Accel_Y", "Accel_Z", "Gyro_X", "Gyro_Y", "Gyro_Z", "Mag_X", "Mag_Y", "Mag_Z"};
        for (int i = 0; i < NUM_AUX_CHANNELS; i++) {
            channelNames[numEegChannels + i] = (i < auxNames.length) ? auxNames[i] : "Aux_" + (i + 1);
        }
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

    // Low-level send without EOT wait (used during handshake)
    private void sendCommandRaw(String command) {
        if (serialPort != null && serialPort.isOpen()) {
            try {
                byte[] data = command.getBytes();
                serialPort.writeBytes(data, data.length);
            } catch (Exception e) {
                println("BoardCytonSerialDirect: Send error: " + e.getMessage());
            }
        }
    }

    // Wait for '$$$' EOT sequence from the board after sending a command
    private boolean waitForEot(long timeoutMs) {
        long start = System.currentTimeMillis();
        eotMatchIndex = 0;
        while ((System.currentTimeMillis() - start) < timeoutMs) {
            int b = ringRead();
            if (b < 0) {
                try { Thread.sleep(1); } catch (Exception e) {}
                continue;
            }
            if ((byte)b == eotSequence[eotMatchIndex]) {
                eotMatchIndex++;
                if (eotMatchIndex >= eotSequence.length) {
                    return true; // Got full $$$
                }
            } else {
                eotMatchIndex = 0;
                // Re-check current byte as possible start of $$$
                if ((byte)b == eotSequence[0]) {
                    eotMatchIndex = 1;
                }
            }
        }
        return false;
    }

    @Override public void insertMarker(double value) {}
    @Override public void insertMarker(int value) {}
    @Override public void setEXGChannelActive(int channelIndex, boolean active) {}
    @Override public boolean isEXGChannelActive(int channelIndex) { return true; }

    // === ImpedanceSettingsBoard ===

    @Override
    public void setCheckingImpedance(int channel, boolean active) {
        isCheckingImpedanceP[channel] = active;
    }

    @Override
    public boolean isCheckingImpedance(int channel) {
        return isCheckingImpedanceN[channel] || isCheckingImpedanceP[channel];
    }

    @Override
    public Integer isCheckingImpedanceOnChannel() {
        for (int i = 0; i < getNumEXGChannels(); i++) {
            if (isCheckingImpedance(i)) return i;
        }
        return null;
    }

    public boolean isCheckingImpedanceNorP(int channel, boolean isN) {
        return isN ? isCheckingImpedanceN[channel] : isCheckingImpedanceP[channel];
    }

    public Pair<Boolean, Integer> isCheckingImpedanceOnAnyChannelsNorP() {
        for (int i = 0; i < getNumEXGChannels(); i++) {
            if (isCheckingImpedanceN[i]) return new ImmutablePair<>(true, i);
            if (isCheckingImpedanceP[i]) return new ImmutablePair<>(false, i);
        }
        return new ImmutablePair<>(null, null);
    }

    // Impedance command: z<channel><p><n>Z, response: <channel><p><n> (p,n = 0-255)
    public Pair<Boolean, String> setCheckingImpedanceCyton(int channel, boolean active, boolean isN) {
        if (active) {
            // Stop streaming before sending impedance command
            if (streaming) {
                sendCommandRaw("s");
                streaming = false;
                try { Thread.sleep(100); } catch (Exception e) {}
            }
            char chanChar = channelSelectForSettings[channel];
            char p = isN ? '0' : '1';
            char n = isN ? '1' : '0';
            String cmd = String.format("z%c%c%cZ", chanChar, p, n);

            // Wait for board to finish sending buffered EEG data after 's' command
            try { Thread.sleep(100); } catch (Exception e) {}
            // Flush any remaining EEG data from ring buffer
            while (ringAvailable() > 0) { ringRead(); }

            sendCommandRaw(cmd);

            // Pause main loop ring buffer drain to avoid data race
            impedanceMode = true;
            // Read impedance response from serial
            boolean gotResponse = waitForImpedanceResponse(channel, 5000);
            impedanceMode = false;

            if (gotResponse && isN) {
                isCheckingImpedanceN[channel] = true;
            } else if (gotResponse && !isN) {
                isCheckingImpedanceP[channel] = true;
            }
            if (gotResponse) {
                // Resume streaming
                sendCommandRaw("b");
                streaming = true;
                if (isN) {
                    isCheckingImpedanceN[channel] = true;
                } else {
                    isCheckingImpedanceP[channel] = true;
                }
                return new ImmutablePair<>(true, "");
            } else {
                return new ImmutablePair<>(false, "No impedance response");
            }
        } else {
            // Turn off impedance check
            if (isN) {
                isCheckingImpedanceN[channel] = false;
            } else {
                isCheckingImpedanceP[channel] = false;
            }
            return new ImmutablePair<>(true, "");
        }
    }

    // Parse impedance response: z<通道><p><n>Z
    // Example: "z450Z" = channel 4, p=5, n=0
    private boolean waitForImpedanceResponse(int expectedChannel, long timeoutMs) {
        long start = System.currentTimeMillis();
        boolean capturing = false;
        StringBuilder response = new StringBuilder();
        StringBuilder rawLog = new StringBuilder();
        while ((System.currentTimeMillis() - start) < timeoutMs) {
            int b = ringRead();
            if (b < 0) {
                try { Thread.sleep(1); } catch (Exception e) {}
                continue;
            }
            char c = (char) b;
            rawLog.append(String.format("%02X ", b));
            if (c == 'z') {
                // Start of impedance response
                capturing = true;
                response.setLength(0);
            } else if (capturing && c == 'Z') {
                // End of impedance response
                capturing = false;
                // Log hex of captured content
                StringBuilder capHex = new StringBuilder();
                for (int i = 0; i < response.length(); i++) {
                    capHex.append(String.format("%02X ", (int)(response.charAt(i) & 0xFF)));
                }
                println("BoardCytonSerialDirect: Impedance captured hex: " + capHex.toString().trim() + " | len=" + response.length());
                if (response.length() >= 3) {
                    parseImpedanceResponse(response.toString());
                    return true;
                }
            } else if (capturing) {
                response.append(c);
            }
        }
        println("BoardCytonSerialDirect: Impedance timeout, raw bytes: [" + rawLog.toString().trim() + "]");
        return false;
    }

    // Parse impedance response: z<ch><p><n>Z where ch is ASCII digit, p and n are binary bytes (0-255)
    // Store result in data_elec_imp_ohm for widget display
    private void parseImpedanceResponse(String resp) {
        try {
            // resp contains the characters between z and Z
            // Channel is ASCII digit(s), p and n may be binary bytes
            if (resp.length() < 3) return;
            int idx = 0;
            int channel = 0;
            // Parse channel number (1 or 2 ASCII digits)
            while (idx < resp.length() && resp.charAt(idx) >= '0' && resp.charAt(idx) <= '9' && idx < 2) {
                channel = channel * 10 + (resp.charAt(idx) - '0');
                idx++;
            }
            if (channel < 1 || channel > getNumEXGChannels()) return;
            int chanIdx = channel - 1;
            // Parse p value (binary byte)
            if (idx < resp.length()) {
                int pVal = resp.charAt(idx) & 0xFF;
                idx++;
                // Parse n value (binary byte)
                int nVal = 0;
                if (idx < resp.length()) {
                    nVal = resp.charAt(idx) & 0xFF;
                }
                // Board returns impedance in kOhms directly, use P pin value only
                data_elec_imp_ohm[chanIdx] = (float)pVal;
                println("BoardCytonSerialDirect: Impedance ch" + channel + " = " + data_elec_imp_ohm[chanIdx] + " ohms (p=" + pVal + ", n=" + nVal + ")");
            }
        } catch (Exception e) {
            println("BoardCytonSerialDirect: Error parsing impedance response: " + e.getMessage());
        }
    }

    // === ADS1299SettingsBoard ===

    @Override
    public ADS1299Settings getADS1299Settings() {
        if (currentADS1299Settings == null) {
            initADS1299Settings();
        }
        return currentADS1299Settings;
    }

    @Override
    public char getChannelSelector(int channel) {
        return channelSelectForSettings[channel];
    }

    @Override
    public double getGain(int channel) {
        return getADS1299Settings().values.gain[channel].getScalar();
    }

    public void forceStopImpedanceFrontEnd(Integer channel, Boolean isN) {
        if (channel == null || isN == null) return;
        if (isN) {
            isCheckingImpedanceN[channel] = false;
        } else {
            isCheckingImpedanceP[channel] = false;
        }
    }

    // Fast reset: clear all impedance flags without per-channel communication
    public void clearAllImpedanceFlags() {
        Arrays.fill(isCheckingImpedanceN, false);
        Arrays.fill(isCheckingImpedanceP, false);
    }

    private int threeBytesToInt(byte b0, byte b1, byte b2) {
        int val = (b0 & 0xFF) | ((b1 & 0xFF) << 8) | ((b2 & 0xFF) << 16);
        if (val >= 0x800000) val -= 0x1000000;
        return val;
    }

    private short twoBytesToShort(byte b0, byte b1) {
        return (short)((b0 & 0xFF) | ((b1 & 0xFF) << 8));
    }

    private void interpretBinaryStream(byte actbyte) {
        switch (packetState) {
            case 0: // Waiting for start byte
                if (actbyte == BYTE_START) {
                    packetBufferLen = 0;
                    packetBuffer[packetBufferLen++] = actbyte;
                    packetPosition = 1;
                    packetState = 1;
                }
                break;

            case 1: // Reading packet body
                if (packetBufferLen < MAX_PACKET_SIZE) {
                    packetBuffer[packetBufferLen++] = actbyte;
                }
                packetPosition++;

                if (expectedPacketSize > 0) {
                    // We know the expected size — only accept end byte at exact position
                    if (packetPosition == expectedPacketSize) {
                        if (actbyte == BYTE_END) {
                            processCompletePacket();
                        } else {
                            // Wrong end byte at expected position — desync, reset
                            packetState = 0;
                        }
                    } else if (packetPosition > expectedPacketSize) {
                        // Overshot — desync
                        packetState = 0;
                    }
                    // Before expectedPacketSize, just keep reading (ignore any 0xC0 in data)
                } else {
                    // Channel count not yet detected — try to detect from packet size
                    // Packet = 2(header) + N*3(EEG) + 18(AUX) + 6(Marker) + 1(end) = 27 + N*3
                    int packetOverhead = PACKET_HEADER + PACKET_AUX_SIZE + PACKET_MARKER_SIZE + PACKET_FOOTER; // 2+18+6+1=27
                    if (actbyte == BYTE_END && packetPosition >= packetOverhead + 3) {
                        // Found end byte, check if packet size is valid
                        int eegBytes = packetPosition - packetOverhead;
                        if (eegBytes > 0 && eegBytes % 3 == 0) {
                            int channels = eegBytes / 3;
                            if (channels >= 1 && channels <= 128) {
                                if (packetPosition == candidatePacketSize) {
                                    candidateCount++;
                                } else {
                                    candidatePacketSize = packetPosition;
                                    candidateCount = 1;
                                }
                                if (candidateCount >= CANDIDATE_THRESHOLD) {
                                    // Confirmed — lock in the channel count
                                    expectedPacketSize = candidatePacketSize;
                                    numEegChannels = channels;
                                    channelsDetected = true;
                                    println("BoardCytonSerialDirect: Auto-detected " + numEegChannels + " EEG channels (" + expectedPacketSize + " bytes/packet)");
                                    if (!preDetectionPhase) {
                                        updateToNChan(numEegChannels);
                                        if (smoothData) {
                                            buffer = new Buffer<double[]>(getTotalChannelCount(), (int)SAMPLE_RATE);
                                        }
                                    }
                                    processCompletePacket();
                                } else {
                                    packetState = 0;
                                }
                            } else {
                                packetState = 0;
                            }
                        } else {
                            packetState = 0;
                        }
                    } else if (packetPosition >= MAX_PACKET_SIZE) {
                        // Too long without end byte — discard
                        packetState = 0;
                    }
                }
                break;
        }
    }

    private void processCompletePacket() {
        packetState = 0;

        // Validate packet: start byte + counter + N*3 EEG + 18 AUX + 6 Marker + end = expectedPacketSize
        if (packetBufferLen != expectedPacketSize) return;
        if (packetBuffer[0] != BYTE_START) return;

        // Parse EEG data: bytes 2..(2+N*3-1)
        int offset = 2; // Skip start byte + frame number
        for (int ch = 0; ch < numEegChannels; ch++) {
            int rawValue = threeBytesToInt(packetBuffer[offset], packetBuffer[offset + 1], packetBuffer[offset + 2]);
            parsedEegValues[ch] = rawValue * scale_fac_uVolts_per_count;
            offset += 3;
        }

        // Parse AUX data: 9 axes × 2 bytes = 18 bytes (accel, gyro, mag)
        for (int ch = 0; ch < NUM_AUX_CHANNELS; ch++) {
            short rawValue = twoBytesToShort(packetBuffer[offset], packetBuffer[offset + 1]);
            parsedAuxValues[ch] = rawValue * scale_fac_accel_G_per_count;
            offset += 2;
        }

        // Parse Marker data: 6 bytes (raw, not scaled)
        for (int ch = 0; ch < NUM_MARKER_CHANNELS; ch++) {
            parsedMarkerValues[ch] = packetBuffer[offset] & 0xFF;
            offset += 1;
        }

        packetCount++;
        lastPacketTime = System.currentTimeMillis();

        if (packetCount % 500 == 0) {
            println("BoardCytonSerialDirect: Packets: " + packetCount);
        }

        if (packetCount <= 3) {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < numEegChannels; i++) {
                sb.append(String.format("ch%d=%.1f ", i, parsedEegValues[i]));
            }
            println("Packet #" + packetCount + " (" + numEegChannels + "ch): " + sb.toString());
        }

        double timestamp = System.currentTimeMillis() / 1000.0;

        // Build sample: [EEG0..N, Aux0..8, Timestamp, SampleIndex, Marker]
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
        // Use first marker channel as the marker value
        sample[numEegChannels + NUM_AUX_CHANNELS + 2] = (NUM_MARKER_CHANNELS > 0) ? parsedMarkerValues[0] : 0;

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
