
////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                    //
//    W_BandPowers.pde                                                                                //
//                                                                                                    //
//    This is a band power visualization widget!                                                      //
//    (Couldn't think up more)                                                                        //
//    This is for visualizing the power of each brainwave band: delta, theta, alpha, beta, gamma      //
//    Averaged over all channels                                                                      //
//                                                                                                    //
//    Created by: Wangshu Sun, May 2017                                                               //
//    Modified by: Richard Waltman, March 2022                                                        //
//                                                                                                    //
////////////////////////////////////////////////////////////////////////////////////////////////////////

class W_BandPower extends Widget {

    // indexes
    private final int DELTA = 0; // 1-4 Hz
    private final int THETA = 1; // 4-8 Hz
    private final int ALPHA = 2; // 8-13 Hz
    private final int BETA = 3; // 13-30 Hz
    private final int GAMMA = 4; // 30-55 Hz
    
    private final int NUM_BANDS = 5;
    private float[] activePower = new float[NUM_BANDS];
    private float[] normalizedBandPowers = new float[NUM_BANDS];

    private GPlot bp_plot;

    private List<controlP5.Controller> cp5ElementsToCheck = new ArrayList<controlP5.Controller>();

    W_BandPower(PApplet _parent) {
        super(_parent); //calls the parent CONSTRUCTOR method of Widget (DON'T REMOVE)

        //Add settings dropdowns
        addDropdown("Smoothing", "Smooth", Arrays.asList(settings.fftSmoothingArray), smoothFac_ind); //smoothFac_ind is a global variable at the top of W_HeadPlot.pde
        addDropdown("UnfiltFilt", "Filters?", Arrays.asList(settings.fftFilterArray), settings.fftFilterSave);

        // Setup for the BandPower plot
        bp_plot = new GPlot(_parent, x, y-navHeight, w, h+navHeight);
        // bp_plot.setPos(x, y+navHeight);
        bp_plot.setDim(w, h);
        bp_plot.setLogScale("y");
        bp_plot.setYLim(0.1, 100);
        bp_plot.setXLim(0, 5);
        bp_plot.getYAxis().setNTicks(9);
        bp_plot.getXAxis().setNTicks(0);
        bp_plot.getTitle().setTextAlignment(LEFT);
        bp_plot.getTitle().setRelativePos(0);
        bp_plot.setAllFontProperties("Arial", 0, 14);
        bp_plot.getYAxis().getAxisLabel().setText("Power — (uV)^2 / Hz");
        bp_plot.getXAxis().setAxisLabelText("EEG Power Bands");
        bp_plot.getXAxis().getAxisLabel().setOffset(42f);
        bp_plot.startHistograms(GPlot.VERTICAL);
        bp_plot.getHistogram().setDrawLabels(true);
        bp_plot.getXAxis().setFontColor(OPENBCI_DARKBLUE);
        bp_plot.getXAxis().setLineColor(OPENBCI_DARKBLUE);
        bp_plot.getXAxis().getAxisLabel().setFontColor(OPENBCI_DARKBLUE);
        bp_plot.getYAxis().setFontColor(OPENBCI_DARKBLUE);
        bp_plot.getYAxis().setLineColor(OPENBCI_DARKBLUE);
        bp_plot.getYAxis().getAxisLabel().setFontColor(OPENBCI_DARKBLUE);

        //setting border of histograms to match BG
        bp_plot.getHistogram().setLineColors(new color[]{
            color(245), color(245), color(245), color(245), color(245)
          }
        );
        //setting bg colors of histogram bars to match the color scheme of the channel colors w/ an opacity of 150/255
        bp_plot.getHistogram().setBgColors(new color[] {
                color((int)channelColors[6], 200),
                color((int)channelColors[4], 200),
                color((int)channelColors[3], 200),
                color((int)channelColors[2], 200), 
                color((int)channelColors[1], 200),
            }
        );
        //setting color of text label for each histogram bar on the x axis
        bp_plot.getHistogram().setFontColor(OPENBCI_DARKBLUE);
    }

    public void update() {
        super.update(); //calls the parent update() method of Widget (DON'T REMOVE)

        GPointsArray bp_points = new GPointsArray(dataProcessing.headWidePower.length);
        bp_points.add(DELTA + 0.5, activePower[DELTA], "DELTA\n0.5-4Hz");
        bp_points.add(THETA + 0.5, activePower[THETA], "THETA\n4-8Hz");
        bp_points.add(ALPHA + 0.5, activePower[ALPHA], "ALPHA\n8-13Hz");
        bp_points.add(BETA + 0.5, activePower[BETA], "BETA\n13-32Hz");
        bp_points.add(GAMMA + 0.5, activePower[GAMMA], "GAMMA\n32-100Hz");
        bp_plot.setPoints(bp_points);

        lockElementsOnOverlapCheck(cp5ElementsToCheck);
    }

    public void draw() {
        super.draw(); //calls the parent draw() method of Widget (DON'T REMOVE)
        pushStyle();

        //remember to refer to x,y,w,h which are the positioning variables of the Widget class
        // Draw the third plot
        bp_plot.beginDraw();
        bp_plot.drawBackground();
        bp_plot.drawBox();
        bp_plot.drawXAxis();
        bp_plot.drawYAxis();
        bp_plot.drawGridLines(GPlot.HORIZONTAL);
        bp_plot.drawHistograms();
        bp_plot.endDraw();

        //for this widget need to redraw the grey bar, bc the FFT plot covers it up...
        fill(200, 200, 200);
        rect(x, y - navHeight, w, navHeight); //button bar

        popStyle();
    }

    public void screenResized() {
        super.screenResized(); //calls the parent screenResized() method of Widget (DON'T REMOVE)

        flexGPlotSizeAndPosition();
    }

    public void mousePressed() {
        super.mousePressed(); //calls the parent mousePressed() method of Widget (DON'T REMOVE)
    }

    void flexGPlotSizeAndPosition() {
        bp_plot.setPos(x, y - navH);
        bp_plot.setOuterDim(w, h + navH);
    }

    public float[] getNormalizedBPSelectedChannels() {
        return normalizedBandPowers;
    }

    //Called in DataProcessing.pde to update data even if widget is closed
    public void updateBandPowerWidgetData() {
        float normalizingSum = 0;
        int visibleCount = 0;

        for (int i = 0; i < NUM_BANDS; i++) {
            float sum = 0;

            for (int j = 0; j < nchan; j++) {
                if (channelVisibility != null && j < channelVisibility.length && !channelVisibility[j]) continue;
                sum += dataProcessing.avgPowerInBins[j][i];
                visibleCount++;
            }

            activePower[i] = visibleCount > 0 ? sum / visibleCount : 0;

            normalizingSum += activePower[i];
        }

        for (int i = 0; i < NUM_BANDS; i++) {
            normalizedBandPowers[i] = normalizingSum > 0 ? activePower[i] / normalizingSum : 0;
        }
    }
};
