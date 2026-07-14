/////////////////////////////////////////////////////////////////////////////////
//
//  Emg_Widget is used to visiualze EMG data by channel, and to trip events
//
//  Created: Colin Fausnaught, December 2016 (with a lot of reworked code from Tao)
//  Modified: Richard Waltman, February 2023
//
//  Custom widget to visiualze EMG data. Features dragable thresholds, serial
//  out communication, channel configuration, digital and analog events.
//
//  KNOWN ISSUES: Cannot resize with window dragging events
//
//  TODO: Add dynamic threshold functionality
////////////////////////////////////////////////////////////////////////////////

class W_emg extends Widget {
    PApplet parent;

    private ControlP5 emgCp5;
    private Button emgSettingsButton;
    private final int EMG_SETTINGS_BUTTON_WIDTH = 125;
    private List<controlP5.Controller> cp5ElementsToCheck;

    W_emg (PApplet _parent) {
        super(_parent); //calls the parent CONSTRUCTOR method of Widget (DON'T REMOVE)
        parent = _parent;

        cp5ElementsToCheck = new ArrayList<controlP5.Controller>();

        emgCp5 = new ControlP5(ourApplet);
        emgCp5.setGraphics(ourApplet, 0,0);
        emgCp5.setAutoDraw(false);

        createEmgSettingsButton();
        cp5ElementsToCheck.add((controlP5.Controller) emgSettingsButton);
    }

    public void update() {
        super.update(); //calls the parent update() method of Widget (DON'T REMOVE)
        lockElementsOnOverlapCheck(cp5ElementsToCheck);
    }

    public void draw() {
        super.draw(); //calls the parent draw() method of Widget (DON'T REMOVE)

        drawEmgVisualizations();

        emgCp5.draw();
    }

    public void screenResized() {
        super.screenResized(); //calls the parent screenResized() method of Widget (DON'T REMOVE)
        emgCp5.setGraphics(ourApplet, 0, 0);
        emgSettingsButton.setPosition(x0 + w - EMG_SETTINGS_BUTTON_WIDTH - 2, y0 + navH + 1);
    }

    public void mousePressed() {
        super.mousePressed(); //calls the parent mousePressed() method of Widget (DON'T REMOVE)
    }

    private void drawEmgVisualizations() {
        pushStyle();

        float rx = x, ry = y, rw = w, rh = h;
        float scaleFactor = 1.0;
        float scaleFactorJaw = 1.5;
        int rowCount = 4;

        // Count visible channels from global visibility
        ArrayList<Integer> visibleChans = new ArrayList<Integer>();
        for (int i = 0; i < nchan; i++) {
            if (channelVisibility != null && i < channelVisibility.length && channelVisibility[i]) {
                visibleChans.add(i);
            }
        }
        int visibleCount = visibleChans.size();
        if (visibleCount == 0) { popStyle(); return; }

        int columnCount = ceil(visibleCount / (rowCount * 1f));
        float rowOffset = rh / rowCount;
        float colOffset = rw / columnCount;
        float currentX, currentY;
        
        EmgSettingsValues emgSettingsValues = dataProcessing.emgSettings.values;

        int channel = 0;
        for (int i = 0; i < rowCount; i++) {
            for (int j = 0; j < columnCount; j++) {

                int index = i * columnCount + j;

                if (index >= visibleCount) {
                    continue;
                }
                
                channel = visibleChans.get(index);

                int colorIndex = channel % 8;

                pushMatrix();

                currentX = rx + j * colOffset;
                currentY = ry + i * rowOffset;
                translate(currentX, currentY);

                //realtime
                fill(channelColors[colorIndex], 200);
                noStroke();
                circle(2*colOffset/8, rowOffset / 2, scaleFactor * emgSettingsValues.getAverageuV(channel));

                //circle for outer threshold
                noFill();
                strokeWeight(1);
                stroke(OPENBCI_DARKBLUE, 150);
                circle(2*colOffset/8, rowOffset / 2, scaleFactor * emgSettingsValues.getUpperThreshold(channel));

                //circle for inner threshold
                stroke(OPENBCI_DARKBLUE, 150);
                circle(2*colOffset/8, rowOffset / 2, scaleFactor * emgSettingsValues.getLowerThreshold(channel));

                int _x = int(5*colOffset/8);
                int _y = int(2 * rowOffset / 8);
                int _w = int(5*colOffset/32);
                int _h = int(4*rowOffset/8);

                //draw normalized bar graph of uV w/ matching channel color
                noStroke();
                fill(channelColors[colorIndex], 200);
                rect(_x, 3*_y + 1, _w, map(emgSettingsValues.getOutputNormalized(channel), 0, 1, 0, (-1) * int((4*rowOffset/8))));

                //draw background bar container for mapped uV value indication
                strokeWeight(1);
                stroke(OPENBCI_DARKBLUE, 150);
                noFill();
                rect(_x, _y, _w, _h);

                //draw channel number at upper left corner of row/column cell
                pushStyle();
                stroke(OPENBCI_DARKBLUE);
                fill(OPENBCI_DARKBLUE);
                textFont(h4, 14);
                text((channel + 1), 10, 20);
                popStyle();

                popMatrix();
            }
        }

        popStyle();
    }

    private void createEmgSettingsButton() {
        emgSettingsButton = createButton(emgCp5, "emgSettingsButton", "EMG Settings", 
                (int) (x0 + w - EMG_SETTINGS_BUTTON_WIDTH - 1), (int) (y0 + navH + 1), 
                EMG_SETTINGS_BUTTON_WIDTH, navH - 3, p5, 12, colorNotPressed, OPENBCI_DARKBLUE);
        emgSettingsButton.setBorderColor(OBJECT_BORDER_GREY);
        emgSettingsButton.onRelease(new CallbackListener() {
            public synchronized void controlEvent(CallbackEvent theEvent) {
                if (!emgSettingsPopupIsOpen) {
                    EmgSettingsUI emgSettingsUI = new EmgSettingsUI();
                }
            }
        });
        emgSettingsButton.setDescription("Click to open the EMG Settings UI to adjust how this metric is calculated.");
    }
};
