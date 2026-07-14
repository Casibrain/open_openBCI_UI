
//////////////////////////////////////////////////////
//                                                  //
//                  W_Spectrogram.pde               //
//                                                  //
//                                                  //
//    Created by: Richard Waltman, September 2019   //
//                                                  //
//////////////////////////////////////////////////////

class W_Spectrogram extends Widget {

    List<controlP5.Controller> cp5ElementsToCheck = new ArrayList<controlP5.Controller>();

    int xPos = 0;
    int hueLimit = 160;

    PImage dataImg;
    int dataImageW = 1800;
    int dataImageH = 200;
    int prevW = 0;
    int prevH = 0;
    float scaledWidth;
    float scaledHeight;
    int graphX = 0;
    int graphY = 0;
    int graphW = 0;
    int graphH = 0;
    int midLineY = 0;

    private int lastShift = 0;
    private int scrollSpeed = 100; // == 10Hz
    private boolean wasRunning = false;

    int paddingLeft = 54;
    int paddingRight = 26;   
    int paddingTop = 8;
    int paddingBottom = 50;
    int numHorizAxisDivs = 3;
    int numVertAxisDivs = 8;
    final int[][] vertAxisLabels = {
        {20, 15, 10, 5, 0, 5, 10, 15, 20},
        {40, 30, 20, 10, 0, 10, 20, 30, 40},
        {60, 45, 30, 15, 0, 15, 30, 45, 60},
        {100, 75, 50, 25, 0, 25,  50, 75, 100},
        {120, 90, 60, 30, 0, 30, 60, 90, 120},
        {250, 188, 125, 63, 0, 63, 125, 188, 250}
    };
    int[] vertAxisLabel;
    final float[][] horizAxisLabels = {
        {30, 25, 20, 15, 10, 5, 0},
        {6, 5, 4, 3, 2, 1, 0},
        {3, 2, 1, 0},
        {1.5, 1, .5, 0},
        {1, .5, 0}
    };
    float[] horizAxisLabel;
    StringList horizAxisLabelStrings;

    float[] topFFTAvg;
    float[] botFFTAvg;

    W_Spectrogram(PApplet _parent){
        super(_parent); //calls the parent CONSTRUCTOR method of Widget (DON'T REMOVE)

        xPos = w - 1; //draw on the right, and shift pixels to the left
        prevW = w;
        prevH = h;
        graphX = x + paddingLeft;
        graphY = y + paddingTop;
        graphW = w - paddingRight - paddingLeft;
        graphH = h - paddingBottom - paddingTop;

        settings.spectMaxFrqSave = 1;
        settings.spectSampleRateSave = 2;
        settings.spectLogLinSave = 0;
        vertAxisLabel = vertAxisLabels[settings.spectMaxFrqSave];
        horizAxisLabel = horizAxisLabels[settings.spectSampleRateSave];
        horizAxisLabelStrings = new StringList();
        //Fetch/calculate the time strings for the horizontal axis ticks
        fetchTimeStrings(numHorizAxisDivs);

        //This is the protocol for setting up dropdowns.
        //Note that these 3 dropdowns correspond to the 3 global functions below
        //You just need to make sure the "id" (the 1st String) has the same name as the corresponding function
        addDropdown("SpectrogramMaxFreq", "Max Freq", Arrays.asList(settings.spectMaxFrqArray), settings.spectMaxFrqSave);
        addDropdown("SpectrogramSampleRate", "Window", Arrays.asList(settings.spectSampleRateArray), settings.spectSampleRateSave);
        addDropdown("SpectrogramLogLin", "Log/Lin", Arrays.asList(settings.fftLogLinArray), settings.spectLogLinSave);

        //Resize the height of the data image using default 
        dataImageH = vertAxisLabel[0] * 2;
        //Create image using correct dimensions! Fixes bug where image size and labels do not align on session start.
        dataImg = createImage(dataImageW, dataImageH, RGB);
    }

    void update(){
        super.update(); //calls the parent update() method of Widget (DON'T REMOVE)

        lockElementsOnOverlapCheck(cp5ElementsToCheck);
        
        if (currentBoard.isStreaming()) {
            //Make sure we are always draw new pixels on the right
            xPos = dataImg.width - 1;
            //Fetch/calculate the time strings for the horizontal axis ticks
            fetchTimeStrings(numHorizAxisDivs);
        }
        
        //State change check
        if (currentBoard.isStreaming() && !wasRunning) {
            onStartRunning();
        } else if (!currentBoard.isStreaming() && wasRunning) {
            onStopRunning();
        }
    }

    private void onStartRunning() {
        wasRunning = true;
        lastShift = millis();
    }

    private void onStopRunning() {
        wasRunning = false;
    }

    public void draw(){
        super.draw(); //calls the parent draw() method of Widget (DON'T REMOVE)

        //put your code here... //remember to refer to x,y,w,h which are the positioning variables of the Widget class
        
        //Scale the dataImage to fit in inside the widget
        float scaleW = float(graphW) / dataImageW;
        float scaleH = float(graphH) / dataImageH;

        pushStyle();
        fill(0);
        rect(x, y, w, h); //draw a black background for the widget
        popStyle();

        //draw the spectrogram if the widget is open, and update pixels if board is streaming data
        if (currentBoard.isStreaming()) {
            pushStyle();
            dataImg.loadPixels();

            //Shift all pixels to the left! (every scrollspeed ms)
            if(millis() - lastShift > scrollSpeed) {
                for (int r = 0; r < dataImg.height; r++) {
                    if (r != 0) {
                        arrayCopy(dataImg.pixels, dataImg.width * r, dataImg.pixels, dataImg.width * r - 1, dataImg.width);
                    } else {
                        //When there would be an ArrayOutOfBoundsException, account for it!
                        arrayCopy(dataImg.pixels, dataImg.width * (r + 1), dataImg.pixels, r * dataImg.width, dataImg.width);
                    }
                }

                lastShift += scrollSpeed;
            }
            //for (int i = 0; i < fftLin_L.specSize() - 80; i++) {
            for (int i = 0; i <= dataImg.height/2; i++) {
                //LEFT SPECTROGRAM ON TOP - use first half of visible channels
                ArrayList<Integer> topChans = getVisibleChannelsTop();
                float hueValue = hueLimit - map((fftAvgs(topChans, i)*32), 0, 256, 0, hueLimit);
                if (settings.spectLogLinSave == 0) {
                    hueValue = map(log10(hueValue), 0, 2, 0, hueLimit);
                }
                colorMode(HSB, 256, 100, 100);
                stroke(int(hueValue), 100, 80);
                int loc = xPos + ((dataImg.height/2 - i) * dataImg.width);
                if (loc >= dataImg.width * dataImg.height) loc = dataImg.width * dataImg.height - 1;
                try {
                    dataImg.pixels[loc] = color(int(hueValue), 100, 80);
                } catch (Exception e) {
                    println("Major drawing error Spectrogram Left image!");
                }

                //RIGHT SPECTROGRAM ON BOTTOM - use second half of visible channels
                ArrayList<Integer> botChans = getVisibleChannelsBot();
                hueValue = hueLimit - map((fftAvgs(botChans, i)*32), 0, 256, 0, hueLimit);
                if (settings.spectLogLinSave == 0) {
                    hueValue = map(log10(hueValue), 0, 2, 0, hueLimit);
                }
                colorMode(HSB, 256, 100, 100);
                stroke(int(hueValue), 100, 80);
                int y_offset = -1;
                loc = xPos + ((i + dataImg.height/2 + y_offset) * dataImg.width);
                if (loc >= dataImg.width * dataImg.height) loc = dataImg.width * dataImg.height - 1;
                try {
                    dataImg.pixels[loc] = color(int(hueValue), 100, 80);
                } catch (Exception e) {
                    println("Major drawing error Spectrogram Right image!");
                }
            }
            dataImg.updatePixels();
            popStyle();
        }
        
        pushMatrix();
        translate(graphX, graphY);
        scale(scaleW, scaleH);
        image(dataImg, 0, 0);
        popMatrix();

        drawAxes(scaleW, scaleH);
        drawCenterLine();
    }

    public void screenResized(){
        super.screenResized(); //calls the parent screenResized() method of Widget (DON'T REMOVE)

        graphX = x + paddingLeft;
        graphY = y + paddingTop;
        graphW = w - paddingRight - paddingLeft;
        graphH = h - paddingBottom - paddingTop;
    }

    void mousePressed(){
        super.mousePressed(); //calls the parent mousePressed() method of Widget (DON'T REMOVE)
    }

    void mouseReleased(){
        super.mouseReleased(); //calls the parent mouseReleased() method of Widget (DON'T REMOVE)

    }

    void drawAxes(float scaledW, float scaledH) {
        
        pushStyle();
            fill(255);
            textSize(14);
            //draw horizontal axis label
            text("Time", x + w/2 - textWidth("Time")/3, y + h - 9);
            noFill();
            stroke(255);
            strokeWeight(2);
            //draw rectangle around the spectrogram
            rect(graphX, graphY, scaledW * dataImageW, scaledH * dataImageH);
        popStyle();

        pushStyle();
            //draw horizontal axis ticks from left to right
            int tickMarkSize = 7; //in pixels
            float horizAxisX = graphX;
            float horizAxisY = graphY + scaledH * dataImageH;
            stroke(255);
            fill(255);
            strokeWeight(2);
            textSize(11);
            for (int i = 0; i <= numHorizAxisDivs; i++) {
                float offset = scaledW * dataImageW * (float(i) / numHorizAxisDivs);
                line(horizAxisX + offset, horizAxisY, horizAxisX + offset, horizAxisY + tickMarkSize);
                if (horizAxisLabelStrings.get(i) != null) {
                    text(horizAxisLabelStrings.get(i), horizAxisX + offset - (int)textWidth(horizAxisLabelStrings.get(i))/2, horizAxisY + tickMarkSize * 3);
                }
            }
        popStyle();
        
        pushStyle();
            pushMatrix();
                rotate(radians(-90));
                translate(-h/2 - textWidth("Frequency (Hz)")/3, 20);
                fill(255);
                textSize(14);
                //draw y axis label
                text("Frequency (Hz)", -y, x);
            popMatrix();
        popStyle();

        pushStyle();
            //draw vertical axis ticks from top to bottom
            float vertAxisX = graphX;
            float vertAxisY = graphY;
            stroke(255);
            fill(255);
            textSize(12);
            strokeWeight(2);
            for (int i = 0; i <= numVertAxisDivs; i++) {
                float offset = scaledH * dataImageH * (float(i) / numVertAxisDivs);
                //if (i <= numVertAxisDivs/2) offset -= 2;
                line(vertAxisX, vertAxisY + offset, vertAxisX - tickMarkSize, vertAxisY + offset);
                if (vertAxisLabel[i] == 0) midLineY = int(vertAxisY + offset);
                offset += paddingTop/2;
                text(vertAxisLabel[i], vertAxisX - tickMarkSize*2 - textWidth(Integer.toString(vertAxisLabel[i])), vertAxisY + offset);
            }
        popStyle();

        drawColorScaleReference();
    }

    void drawCenterLine() {
        //draw a thick line down the middle to separate the two plots
        pushStyle();
        stroke(255);
        strokeWeight(3);
        line(graphX, midLineY, graphX + graphW, midLineY);
        popStyle();
    }

    void drawColorScaleReference() {
        int colorScaleHeight = 128;
        //Dynamically scale the Log/Lin amplitude-to-color reference line. If it won't fit, don't draw it.
        if (graphH < colorScaleHeight) {
            colorScaleHeight = int(h * 1/2);
            if (colorScaleHeight > graphH) {
                return;
            }
        }
        pushStyle();
            //draw color scale reference to the right of the spectrogram
            for (int i = 0; i < colorScaleHeight; i++) {
                float hueValue = hueLimit - map(i * 2, 0, colorScaleHeight*2, 0, hueLimit);
                if (settings.spectLogLinSave == 0) {
                    hueValue = map(log(hueValue) / log(10), 0, 2, 0, hueLimit);
                }
                //println(hueValue);
                // colorMode is HSB, the range for hue is 256, for saturation is 100, brightness is 100.
                colorMode(HSB, 256, 100, 100);
                // color for stroke is specified as hue, saturation, brightness.
                stroke(ceil(hueValue), 100, 80);
                strokeWeight(10);
                point(x + w - paddingRight/2 + 1, midLineY + colorScaleHeight/2 - i);
            }
        popStyle();
    }

    // Get first half of visible channels for top spectrogram
    private ArrayList<Integer> getVisibleChannelsTop() {
        ArrayList<Integer> all = getVisibleChannels();
        ArrayList<Integer> top = new ArrayList<Integer>();
        int half = all.size() / 2;
        for (int i = 0; i < half; i++) top.add(all.get(i));
        if (top.isEmpty() && all.size() > 0) top.add(all.get(0));
        return top;
    }

    // Get second half of visible channels for bottom spectrogram
    private ArrayList<Integer> getVisibleChannelsBot() {
        ArrayList<Integer> all = getVisibleChannels();
        ArrayList<Integer> bot = new ArrayList<Integer>();
        int half = all.size() / 2;
        for (int i = half; i < all.size(); i++) bot.add(all.get(i));
        if (bot.isEmpty() && all.size() > 1) bot.add(all.get(1));
        return bot;
    }

    // Get all visible channels from global visibility
    private ArrayList<Integer> getVisibleChannels() {
        ArrayList<Integer> visible = new ArrayList<Integer>();
        for (int i = 0; i < nchan; i++) {
            if (channelVisibility != null && i < channelVisibility.length && channelVisibility[i]) {
                visible.add(i);
            }
        }
        return visible;
    }

    void activateDefaultChannels() {
        // Default channels now come from global visibility
    }

    void flexSpectrogramSizeAndPosition() {
        // No longer needed - graph position is fixed
    }

    void setScrollSpeed(int i) {
        scrollSpeed = i;
    }

    float fftAvgs(List<Integer> _activeChan, int freqBand) {
        float sum = 0f;
        for (int i = 0; i < _activeChan.size(); i++) {
            sum += fftBuff[_activeChan.get(i)].getBand(freqBand);
        }
        return sum / _activeChan.size();
    }

    void fetchTimeStrings(int numAxisTicks) {
        horizAxisLabelStrings.clear();
        LocalDateTime time;
        DateTimeFormatter formatter = DateTimeFormatter.ofPattern("HH:mm:ss");

        if (getCurrentTimeStamp() == 0) {
            time = LocalDateTime.now();
        } else {
            time = LocalDateTime.ofInstant(Instant.ofEpochMilli(getCurrentTimeStamp()), 
                                            TimeZone.getDefault().toZoneId()); 
        }
        
        for (int i = 0; i <= numAxisTicks; i++) {
            long l = (long)(horizAxisLabel[i] * 60f);
            LocalDateTime t = time.minus(l, ChronoUnit.SECONDS);
            horizAxisLabelStrings.append(t.format(formatter));
        }
    }

    //Identical to the method in TimeSeries, but allows spectrogram to get the data directly from the playback data in the background
    //Find times to display for playback position
    private long getCurrentTimeStamp() {
        //return current playback time
        List<double[]> currentData = currentBoard.getData(1);
        int timeStampChan = currentBoard.getTimestampChannel();
        long timestampMS = (long)(currentData.get(0)[timeStampChan] * 1000.0);
        return timestampMS;
    }
};

//These functions need to be global! These functions are activated when an item from the corresponding dropdown is selected
//triggered when there is an event in the Spectrogram Widget MaxFreq. Dropdown
void SpectrogramMaxFreq(int n) {
    settings.spectMaxFrqSave = n;
    //reset the vertical axis labels
    w_spectrogram.vertAxisLabel = w_spectrogram.vertAxisLabels[n];
    //Resize the height of the data image
    w_spectrogram.dataImageH = w_spectrogram.vertAxisLabel[0] * 2;
    //overwrite the existing image because the sample rate is about to change
    w_spectrogram.dataImg = createImage(w_spectrogram.dataImageW, w_spectrogram.dataImageH, RGB);
}

void SpectrogramSampleRate(int n) {
    settings.spectSampleRateSave = n;
    //overwrite the existing image because the sample rate is about to change
    w_spectrogram.dataImg = createImage(w_spectrogram.dataImageW, w_spectrogram.dataImageH, RGB);
    w_spectrogram.horizAxisLabel = w_spectrogram.horizAxisLabels[n];
    if (n == 0) {
        w_spectrogram.numHorizAxisDivs = 6;
        w_spectrogram.setScrollSpeed(1000);
    } else if (n == 1) {
        w_spectrogram.numHorizAxisDivs = 6;
        w_spectrogram.setScrollSpeed(200);
    } else if (n == 2) {
        w_spectrogram.numHorizAxisDivs = 3;
        w_spectrogram.setScrollSpeed(100);
    } else if (n == 3) {
        w_spectrogram.numHorizAxisDivs = 3;
        w_spectrogram.setScrollSpeed(50);
    } else if (n == 4) {
        w_spectrogram.numHorizAxisDivs = 2;
        w_spectrogram.setScrollSpeed(25);
    }
    w_spectrogram.horizAxisLabelStrings.clear();
    w_spectrogram.fetchTimeStrings(w_spectrogram.numHorizAxisDivs);
}

void SpectrogramLogLin(int n) {
    settings.spectLogLinSave = n;
}