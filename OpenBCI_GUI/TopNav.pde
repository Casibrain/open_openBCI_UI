///////////////////////////////////////////////////////////////////////////////////////
//
//  Created by Conor Russomanno, 11/3/16
//  Extracting old code Gui_Manager.pde, adding new features for GUI v2 launch
//
//  Edited by Richard Waltman 9/24/18
//  Refactored by Richard Waltman 11/9/2020
///////////////////////////////////////////////////////////////////////////////////////

import java.awt.Desktop;
import java.net.*;
import java.nio.file.*;
import javax.swing.JFrame;
import javax.swing.JPanel;
import java.awt.event.MouseEvent;
import java.awt.event.MouseListener;
import java.awt.event.MouseMotionListener;
import java.awt.event.WindowAdapter;
import java.awt.Graphics;
import java.awt.Graphics2D;
import java.awt.Color;
import java.awt.Font;
import java.awt.FontMetrics;
import java.awt.BasicStroke;

class TopNav {

    private final color TOPNAV_DARKBLUE = OPENBCI_BLUE;
    private final color SUBNAV_LIGHTBLUE = buttonsLightBlue;
    private color strokeColor = OPENBCI_DARKBLUE;

    private ControlP5 topNav_cp5;

    public Button controlPanelCollapser;

    public Button toggleDataStreamingButton;

    public Button filtersButton;
    public Button smoothingButton;
    public Button channelSelectButton;

    public Button debugButton;

    public Button layoutButton;
    public Button settingsButton;

    public LayoutSelector layoutSelector;
    public ConfigSelector configSelector;
    public ChannelSelectorPopup channelSelectorPopup;
    private int previousSystemMode = 0;

    private boolean secondaryNavInit = false;

    private final int PAD_3 = 3;
    private final int DEBUG_BUT_W = 33;
    private final int TOPRIGHT_BUT_W = 80;
    private final int DATASTREAM_BUT_W = 170;
    private final int SUBNAV_BUT_Y = 35;
    private final int SUBNAV_BUT_W = 70;
    private final int SUBNAV_BUT_H = 26;
    private final int TOPNAV_BUT_H = SUBNAV_BUT_H;

    private boolean topNavDropdownMenuIsOpen = false;

    TopNav() {
        int controlPanel_W = 256;

        //Instantiate local cp5 for this box
        topNav_cp5 = new ControlP5(ourApplet);
        topNav_cp5.setGraphics(ourApplet, 0, 0);
        topNav_cp5.setAutoDraw(false);

        //TOP LEFT OF GUI
        createControlPanelCollapser("System Control Panel", PAD_3, PAD_3, controlPanel_W, TOPNAV_BUT_H, h3, 16, TOPNAV_DARKBLUE, WHITE);

        //TOP RIGHT OF GUI, FROM LEFT<---Right
        createDebugButton(" ", width - DEBUG_BUT_W - PAD_3, PAD_3, DEBUG_BUT_W, TOPNAV_BUT_H, h3, 16, TOPNAV_DARKBLUE, WHITE);

        //SUBNAV TOP RIGHT
        createTopNavSettingsButton("Settings", width - SUBNAV_BUT_W - PAD_3, SUBNAV_BUT_Y, SUBNAV_BUT_W, SUBNAV_BUT_H, h4, 14, SUBNAV_LIGHTBLUE, WHITE);

        layoutSelector = new LayoutSelector();
        configSelector = new ConfigSelector();

        //updateNavButtonsBasedOnColorScheme();
    }

    void initSecondaryNav() {

        boolean needToMakeSmoothingButton = (currentBoard instanceof SmoothingCapableBoard) && smoothingButton == null;

        if (!secondaryNavInit) {
            //Buttons on the left side of the GUI secondary nav bar
            createToggleDataStreamButton(stopButton_pressToStart_txt, PAD_3, SUBNAV_BUT_Y, DATASTREAM_BUT_W, SUBNAV_BUT_H, h4, 14, TURN_ON_GREEN, OPENBCI_DARKBLUE);
            createFiltersButton("Filters", PAD_3*2 + toggleDataStreamingButton.getWidth(), SUBNAV_BUT_Y, SUBNAV_BUT_W, SUBNAV_BUT_H, h4, 14, SUBNAV_LIGHTBLUE, WHITE);

            //Appears at Top Right SubNav while in a Session
            createLayoutButton("Layout", width - 3 - 60, SUBNAV_BUT_Y, 60, SUBNAV_BUT_H, h4, 14, SUBNAV_LIGHTBLUE, WHITE);
            secondaryNavInit = true;
        }

        if (needToMakeSmoothingButton) {
            int pos_x = (int)filtersButton.getPosition()[0] + filtersButton.getWidth() + PAD_3;
            //Make smoothing button wider than most other topnav buttons to fit text comfortably
            createSmoothingButton(getSmoothingString(), pos_x, SUBNAV_BUT_Y, SUBNAV_BUT_W + 48, SUBNAV_BUT_H, h4, 14, SUBNAV_LIGHTBLUE, WHITE);

            //Add channel select button after smoothing button
            int chanPos_x = (int)smoothingButton.getPosition()[0] + smoothingButton.getWidth() + PAD_3;
            createChannelSelectButton("Channels", chanPos_x, SUBNAV_BUT_Y, SUBNAV_BUT_W + 20, SUBNAV_BUT_H, h4, 14, SUBNAV_LIGHTBLUE, WHITE);
        }
        
        
        //updateSecondaryNavButtonsColor();
    }

    void update() {
        //Make sure these buttons don't get accidentally locked
        if (systemMode >= SYSTEMMODE_POSTINIT) {
            setLockTopLeftSubNavCp5Objects(controlPanel.isOpen);
        }

        if (previousSystemMode != systemMode) {
            if (systemMode >= SYSTEMMODE_POSTINIT) {
                layoutSelector.update();
                if (int(settingsButton.getPosition()[0]) != width - (SUBNAV_BUT_W*2) + 3) {
                    settingsButton.setPosition(width - (SUBNAV_BUT_W*2) + 3, SUBNAV_BUT_Y);
                    verbosePrint("TopNav: Updated Settings Button Position");
                }
            } else {
                if (int(settingsButton.getPosition()[0]) != width - 70 - 3) {
                    settingsButton.setPosition(width - 70 - 3, SUBNAV_BUT_Y);
                    verbosePrint("TopNav: Updated Settings Button Position");
                }
            }
            configSelector.update();
            previousSystemMode = systemMode;
        }
        
        boolean topNavSubClassIsOpen = layoutSelector.isVisible || configSelector.isVisible;
        setDropdownMenuIsOpen(topNavSubClassIsOpen);
    }

    void draw() {
        PImage logo;
        color topNavBg;
        color subNavBg;
        if (colorScheme == COLOR_SCHEME_ALTERNATIVE_A) {
            topNavBg = OPENBCI_BLUE;
            subNavBg = SUBNAV_LIGHTBLUE;
            logo = logo_white;
        } else {
            topNavBg = color(255);
            subNavBg = color(229);
            logo = logo_black;
        }

        pushStyle();
        //stroke(OPENBCI_DARKBLUE);
        fill(topNavBg);
        rect(0, 0, width, navBarHeight);
        //noStroke();
        stroke(strokeColor);
        fill(subNavBg);
        rect(-1, navBarHeight, width+2, navBarHeight);
        popStyle();

        //hide the center logo if buttons would overlap it
        if (width > 860) {
            //this is the center logo
            image(logo, width/2 - (128/2) - 2, 1, 128, 29);
        }

        //Draw these buttons during a Session
        boolean isSession = systemMode == SYSTEMMODE_POSTINIT;
        if (secondaryNavInit) {
            toggleDataStreamingButton.setVisible(isSession);
            filtersButton.setVisible(isSession);
            layoutButton.setVisible(isSession);
           
        }
        if (smoothingButton != null) {
            smoothingButton.setVisible(isSession);
        }

        //Draw CP5 Objects
        topNav_cp5.draw();

        //Draw everything in these selector boxes above all topnav cp5 objects
        layoutSelector.draw();
        configSelector.draw();

        //Draw Console Log Image on top of cp5 object
        PImage _logo = (colorScheme == COLOR_SCHEME_DEFAULT) ? consoleImgBlue : consoleImgWhite;
        image(_logo, debugButton.getPosition()[0] + 6, debugButton.getPosition()[1] + 2, 22, 22);        
        

    }

    void screenHasBeenResized(int _x, int _y) {
        topNav_cp5.setGraphics(ourApplet, 0, 0); //Important!
        debugButton.setPosition(width - debugButton.getWidth() - PAD_3, PAD_3);
        settingsButton.setPosition(width - settingsButton.getWidth() - PAD_3, SUBNAV_BUT_Y);

        if (systemMode == SYSTEMMODE_POSTINIT) {
            toggleDataStreamingButton.setPosition(PAD_3, SUBNAV_BUT_Y);
            filtersButton.setPosition(PAD_3*2 + toggleDataStreamingButton.getWidth(), SUBNAV_BUT_Y);

            layoutButton.setPosition(width - 3 - layoutButton.getWidth(), SUBNAV_BUT_Y);
            settingsButton.setPosition(width - (settingsButton.getWidth()*2) + PAD_3, SUBNAV_BUT_Y);
            //Make sure to re-position UI in selector boxes
            layoutSelector.screenResized();
        }
        
        configSelector.screenResized();
    }

    void mousePressed() {
        layoutSelector.mousePressed();     //pass mousePressed along to layoutSelector
        configSelector.mousePressed();
    }

    void mouseReleased() {
        layoutSelector.mouseReleased();    //pass mouseReleased along to layoutSelector
        configSelector.mouseReleased();
    } //end mouseReleased

    public void updateSmoothingButtonText() {
        smoothingButton.getCaptionLabel().setText(getSmoothingString());
    }

    private String getSmoothingString() {
        return ((SmoothingCapableBoard)currentBoard).getSmoothingActive() ? "Smoothing On" : "Smoothing Off";
    }

    private Button createTNButton(String name, String text, int _x, int _y, int _w, int _h, PFont _font, int _fontSize, color _bg, color _textColor) {
        return createButton(topNav_cp5, name, text, _x, _y, _w, _h, 0, _font, _fontSize, _bg, _textColor, BUTTON_HOVER, BUTTON_PRESSED, OPENBCI_DARKBLUE, -1);
    }

    private void createControlPanelCollapser(String text, int _x, int _y, int _w, int _h, PFont font, int _fontSize, color _bg, color _textColor) {
        controlPanelCollapser = createTNButton("controlPanelCollapser", text, _x, _y, _w, _h, font, _fontSize, _bg, _textColor);
        controlPanelCollapser.setSwitch(true);
        controlPanelCollapser.setOn();
        controlPanelCollapser.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
               if (controlPanelCollapser.isOn()) {
                   controlPanel.openPanel();
               } else {
                   controlPanel.close();
               }
            }
        });
    }

    private void createToggleDataStreamButton(String text, int _x, int _y, int _w, int _h, PFont font, int _fontSize, color _bg, color _textColor) {
        toggleDataStreamingButton = createTNButton("toggleDataStreamingButton", text, _x, _y, _w, _h, font, _fontSize, _bg, _textColor);
        toggleDataStreamingButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
               stopButtonWasPressed();
            }
        });
        toggleDataStreamingButton.setDescription("Press this button to Stop/Start the data stream. Or press <SPACEBAR>");
    }

    private void createFiltersButton(String text, int _x, int _y, int _w, int _h, PFont font, int _fontSize, color _bg, color _textColor) {
        filtersButton = createTNButton("filtersButton", text, _x, _y, _w, _h, font, _fontSize, _bg, _textColor);
        filtersButton.onRelease(new CallbackListener() {
            public synchronized void controlEvent(CallbackEvent theEvent) {
                if (!filterUIPopupIsOpen) {
                    FilterUIPopup filtersUI = new FilterUIPopup();
                }
            }
        });
        filtersButton.setDescription("Here you can adjust the Filters that are applied to \"Filtered\" data.");
    }

    private void createSmoothingButton(String text, int _x, int _y, int _w, int _h, PFont font, int _fontSize, final color _bg, color _textColor) {
        SmoothingCapableBoard smoothBoard = (SmoothingCapableBoard)currentBoard;
        color bgColor = smoothBoard.getSmoothingActive() ? _bg : BUTTON_LOCKED_GREY;
        smoothingButton = createTNButton("smoothingButton", text, _x, _y, _w, _h, font, _fontSize, bgColor, _textColor);
        smoothingButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
                SmoothingCapableBoard smoothBoard = (SmoothingCapableBoard)currentBoard;
                smoothBoard.setSmoothingActive(!smoothBoard.getSmoothingActive());
                smoothingButton.getCaptionLabel().setText(getSmoothingString());
                color _bgColor = smoothBoard.getSmoothingActive() ? _bg : BUTTON_LOCKED_GREY;
                smoothingButton.setColorBackground(_bgColor);
            }
        });
        smoothingButton.setDescription("The default settings for the Cyton Dongle driver can make data appear \"choppy.\" This feature will \"smooth\" the data for you. Click \"Help\" -> \"Cyton Driver Fix\" for more info. Clicking here will toggle this setting.");
    }

    private void createChannelSelectButton(String text, int _x, int _y, int _w, int _h, PFont font, int _fontSize, color _bg, color _textColor) {
        channelSelectButton = createTNButton("channelSelectButton", text, _x, _y, _w, _h, font, _fontSize, _bg, _textColor);
        channelSelectButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
                channelSelectorPopup = new ChannelSelectorPopup();
            }
        });
        channelSelectButton.setDescription("Click to configure which EEG channels are visible across all widgets.");
    }

    private void createLayoutButton(String text, int _x, int _y, int _w, int _h, PFont font, int _fontSize, color _bg, color _textColor) {
        layoutButton = createTNButton("layoutButton", text, _x, _y, _w, _h, font, _fontSize, _bg, _textColor);
        layoutButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
                //make sure that you can't open the layout selector accidentally
                layoutSelector.toggleVisibility();
            }
        });
        layoutButton.setDescription("Here you can alter the overall layout of the GUI, allowing for different container configurations with more or less widgets.");
    }

    private void createDebugButton(String text, int _x, int _y, int _w, int _h, PFont font, int _fontSize, color _bg, color _textColor) {
        debugButton = createTNButton("debugButton", text, _x, _y, _w, _h, font, _fontSize, _bg, _textColor);
        debugButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
               ConsoleWindow.display();
            }
        });
        debugButton.setDescription("Click to open the Console Log window.");
    }

    private void createTopNavSettingsButton(String text, int _x, int _y, int _w, int _h, PFont font, int _fontSize, color _bg, color _textColor) {
        settingsButton = createTNButton("settingsButton", text, _x, _y, _w, _h, font, _fontSize, _bg, _textColor);
        settingsButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
                configSelector.toggleVisibility();
            }
        });
        settingsButton.setDescription("Save and Load GUI Settings! Click Default to revert to factory settings.");
    }

    //Execute this function whenver the stop button is pressed
    public void stopButtonWasPressed() {

        //Exit method if doing Cyton impedance check. Avoids a BrainFlow error.
        if (currentBoard instanceof BoardCyton && w_cytonImpedance != null) {
            Integer checkingImpOnChan = ((ImpedanceSettingsBoard)currentBoard).isCheckingImpedanceOnChannel();
            //println("isCheckingImpedanceOnAnythingEZCHECK==",w_cytonImpedance.isCheckingImpedanceOnAnything);
            if (checkingImpOnChan != null || w_cytonImpedance.cytonMasterImpedanceCheckIsActive() || w_cytonImpedance.isCheckingImpedanceOnAnything) {
                PopupMessage msg = new PopupMessage("Busy Checking Impedance", "Please turn off impedance check to begin recording the data stream.");
                println("OpenBCI_GUI::Cyton: Please turn off impedance check to begin recording the data stream.");
                return;
            }
        }

        //toggle the data transfer state of the ADS1299...stop it or start it...
        if (currentBoard.isStreaming()) {
            output("openBCI_GUI: stopButton was pressed. Stopping data transfer, wait a few seconds.");
            stopRunning();
            if (!currentBoard.isStreaming()) {
                toggleDataStreamingButton.getCaptionLabel().setText(stopButton_pressToStart_txt);
                toggleDataStreamingButton.setColorBackground(TURN_ON_GREEN);
            }
        } else { //not running
            output("openBCI_GUI: startButton was pressed. Starting data transfer, wait a few seconds.");
            startRunning();
            if (currentBoard.isStreaming()) {
                toggleDataStreamingButton.getCaptionLabel().setText(stopButton_pressToStop_txt);
                toggleDataStreamingButton.setColorBackground(TURN_OFF_RED);
                nextPlayback_millis = millis();  //used for synthesizeData and readFromFile.  This restarts the clock that keeps the playback at the right pace.
            }
        }
    }

    public boolean dataStreamingButtonIsActive() {
        return toggleDataStreamingButton.getCaptionLabel().getText().equals(stopButton_pressToStop_txt);
    }

    public void resetStartStopButton() {
        if (toggleDataStreamingButton != null) {
            toggleDataStreamingButton.getCaptionLabel().setText(stopButton_pressToStart_txt);
            toggleDataStreamingButton.setColorBackground(TURN_ON_GREEN);
        }
    }

    public void destroySmoothingButton() {
        topNav_cp5.remove("smoothingButton");
        smoothingButton = null;
    }

    public void setLockTopLeftSubNavCp5Objects(boolean _b) {
        toggleDataStreamingButton.setLock(_b);
        filtersButton.setLock(_b);
    }

    public boolean getDropdownMenuIsOpen() {
        return topNavDropdownMenuIsOpen;
    }

    public void setDropdownMenuIsOpen(boolean b) {
        topNavDropdownMenuIsOpen = b;
    }
}

class LayoutSelector {

    public int x, y, w, h, margin, b_w, b_h;
    public boolean isVisible;
    private ControlP5 layout_cp5;
    public ArrayList<Button> layoutOptions;

    LayoutSelector() {
        w = 180;
        x = width - w - 3;
        y = (navBarHeight * 2) - 3;
        margin = 6;
        b_w = (w - 5*margin)/4;
        b_h = b_w;
        h = margin*4 + b_h*3;

        isVisible = false;
        
        //Instantiate local cp5 for this box
        layout_cp5 = new ControlP5(ourApplet);
        layout_cp5.setGraphics(ourApplet, 0,0);
        layout_cp5.setAutoDraw(false);

        layoutOptions = new ArrayList<Button>();
        addLayoutOptionButtons();
    }

    public void update() {
        if (isVisible) { //only update if visible
            // //close dropdown when mouse leaves
            // if ((mouseX < x || mouseX > x + w || mouseY < y || mouseY > y + h) && !topNav.layoutButton.isMouseHere()){
            //   toggleVisibility();
            // }
        }

        //Update the X position of this box on every update
        x = width - w - 3;
    }

    public void draw() {
        if (isVisible) { //only draw if visible
            pushStyle();

            stroke(OPENBCI_DARKBLUE);
            // fill(229); //bg
            fill(57, 128, 204); //bg
            rect(x, y, w, h);

            fill(57, 128, 204);
            // fill(177, 184, 193);
            noStroke();
            rect(x+w-(topNav.layoutButton.getWidth()-1), y, (topNav.layoutButton.getWidth()-1), 1);

            popStyle();

            layout_cp5.draw();
        }
    }

    public void isMouseHere() {
    }

    public void mousePressed() {
    }

    public void mouseReleased() {
        //only allow button interactivity if isVisible==true
        if (isVisible) {
            if ((mouseX < x || mouseX > x + w || mouseY < y || mouseY > y + h) && !topNav.layoutButton.isInside()) {
                toggleVisibility();
            }

        }
    }

    void screenResized() {
        //update position of outer box and buttons
        //int oldX = x;
        x = width - w - 3;
        //int dx = oldX - x;
        layout_cp5.setGraphics(ourApplet, 0,0);

        for (int i = 0; i < layoutOptions.size(); i++) {
            int row = (i/4)%4;
            int column = i%4;
            layoutOptions.get(i).setPosition(x + (column+1)*margin + (b_w*column), y + (row+1)*margin + row*b_h);
        }
    }

    void toggleVisibility() {
        isVisible = !isVisible;
        if (isVisible) {
            //the very convoluted way of locking all controllers of a single controlP5 instance...
            for (int i = 0; i < wm.widgets.size(); i++) {
                for (int j = 0; j < wm.widgets.get(i).cp5_widget.getAll().size(); j++) {
                    wm.widgets.get(i).cp5_widget.getController(wm.widgets.get(i).cp5_widget.getAll().get(j).getAddress()).lock();
                }
            }
        } else {
            //the very convoluted way of unlocking all controllers of a single controlP5 instance...
            for (int i = 0; i < wm.widgets.size(); i++) {
                for (int j = 0; j < wm.widgets.get(i).cp5_widget.getAll().size(); j++) {
                    wm.widgets.get(i).cp5_widget.getController(wm.widgets.get(i).cp5_widget.getAll().get(j).getAddress()).unlock();
                }
            }
        }
    }

    private void addLayoutOptionButtons() {
        final int numLayouts = 12;
        for (int i = 0; i < numLayouts; i++) {
            int row = (i/4)%4;
            int column = i%4;
            final int layoutNumber = i;
            Button tempLayoutButton = createButton(layout_cp5, "layoutButton"+i, "", x + (column+1)*margin + (b_w*column), y + (row+1)*margin + (row*b_h), b_w, b_h);
            PImage tempBackgroundImage = loadImage("layout_buttons/layout_"+(i+1)+".png");
            tempBackgroundImage.resize(b_w, b_h);
            tempLayoutButton.setImage(tempBackgroundImage);
            tempLayoutButton.setForceDrawBackground(true);
            tempLayoutButton.onRelease(new CallbackListener() {
                public void controlEvent(CallbackEvent theEvent) {
                    output("Layout [" + (layoutNumber) + "] selected.");
                    toggleVisibility(); //shut layoutSelector if something is selected
                    wm.setNewContainerLayout(layoutNumber); //have WidgetManager update Layout and active widgets
                    settings.currentLayout = layoutNumber; //copy this value to be used when saving Layout setting
                }
            });
            layoutOptions.add(tempLayoutButton);
        }
    }
}

class ConfigSelector {
    private int x, y, w, h, margin, b_w, b_h;
    private boolean clearAllSettingsPressed;
    public boolean isVisible;
    private ControlP5 settings_cp5;
    private Button expertMode;
    private Button saveSessionSettings;
    private Button loadSessionSettings;
    private Button defaultSessionSettings;
    private Button clearAllGUISettings;
    private Button clearAllSettingsNo;
    private Button clearAllSettingsYes;

    private int configHeight = 0;

    private int osPadding = 0;
    private int osPadding2 = 0;
    private int buttonSpacer = 0;

    ConfigSelector() {
        int _padding = (systemMode == SYSTEMMODE_POSTINIT) ? -3 : 3;
        w = 140;
        x = width - w - _padding;
        y = (navBarHeight * 2) - 3;
        margin = 6;
        b_w = w - margin*2;
        b_h = 22;
        h = margin*9 + b_h*8;
        //makes the setting text "are you sure" display correctly on linux
        osPadding = isLinux() ? -3 : -2;
        osPadding2 = isLinux() ? 5 : 0;

        //Instantiate local cp5 for this box
        settings_cp5 = new ControlP5(ourApplet);
        settings_cp5.setGraphics(ourApplet, 0,0);
        settings_cp5.setAutoDraw(false);

        isVisible = false;

        int buttonNumber = 0;
        createExpertModeButton("expertMode", "Turn Expert Mode On", x + margin, y + margin*(buttonNumber+1) + b_h*(buttonNumber), b_w, b_h);
        buttonNumber++;
        createSaveSettingsButton("saveSessionSettings", "Save", x + margin, y + margin*(buttonNumber+1) + b_h*(buttonNumber), b_w, b_h);
        buttonNumber++;
        createLoadSettingsButton("loadSessionSettings", "Load", x + margin, y + margin*(buttonNumber+1) + b_h*(buttonNumber), b_w, b_h);
        buttonNumber++;
        createDefaultSettingsButton("defaultSessionSettings", "Default", x + margin, y + margin*(buttonNumber+1) + b_h*(buttonNumber), b_w, b_h);
        buttonNumber++;
        createClearAllSettingsButton("clearAllGUISettings", "Clear All", x + margin, y + margin*(buttonNumber+1) + b_h*(buttonNumber), b_w, b_h);
        buttonNumber += 2;
        createClearSettingsNoButton("clearAllSettingsNo", "No", x + margin, y + margin*(buttonNumber+1) + b_h*(buttonNumber), b_w, b_h);
        buttonNumber++;
        createClearSettingsYesButton("clearAllSettingsYes", "Yes", x + margin, y + margin*(buttonNumber+1) + b_h*(buttonNumber), b_w, b_h);
    }

    public void update() {
    }

    public void draw() {
        if (isVisible) { //only draw if visible
            pushStyle();

            stroke(OPENBCI_DARKBLUE);
            fill(57, 128, 204); //bg
            rect(x, y, w, h);

            boolean isSessionStarted = (systemMode == SYSTEMMODE_POSTINIT);
            saveSessionSettings.setVisible(isSessionStarted);
            loadSessionSettings.setVisible(isSessionStarted);
            defaultSessionSettings.setVisible(isSessionStarted);

            if (clearAllSettingsPressed) {
                textFont(p2, 16);
                fill(255);
                textAlign(CENTER);
                text("Are You Sure?", x + w/2, clearAllGUISettings.getPosition()[1] + b_h*2);
            }
            clearAllSettingsYes.setVisible(clearAllSettingsPressed);
            clearAllSettingsNo.setVisible(clearAllSettingsPressed);

            fill(57, 128, 204);
            noStroke();
            //This makes the dropdown box look like it's apart of the button by drawing over the part that overlaps
            rect(x+w-(topNav.settingsButton.getWidth()-1), y, (topNav.settingsButton.getWidth()-1), 1);

            popStyle();

            settings_cp5.draw();
        }
    }

    public void isMouseHere() {
    }

    public void mousePressed() {
    }

    public void mouseReleased() {
        //only allow button interactivity if isVisible==true
        if (isVisible) {
            if ((mouseX < x || mouseX > x + w || mouseY < y || mouseY > y + h) && !topNav.settingsButton.isInside()) {
                toggleVisibility();
                clearAllSettingsPressed = false;
            }
        }
    }

    public void screenResized() {
        settings_cp5.setGraphics(ourApplet, 0,0);
        updateConfigButtonPositions();
    }

    private void updateConfigButtonPositions() {
        //update position of outer box and buttons
        final boolean isSessionStarted = (systemMode == SYSTEMMODE_POSTINIT);
        int oldX = x;
        int multiplier = isSessionStarted ? 3 : 2;
        int _padding = isSessionStarted ? -3 : 3;
        x = width - 70*multiplier - _padding;
        int dx = oldX - x;

        h = !isSessionStarted ? margin*3 + b_h*2 : margin*6 + b_h*5;

        //Update the Y position for the clear settings buttons
        float clearSettingsButtonY = !isSessionStarted ? 
            expertMode.getPosition()[1] + margin + b_h : 
            defaultSessionSettings.getPosition()[1] + margin + b_h;
        clearAllGUISettings.setPosition(clearAllGUISettings.getPosition()[0], clearSettingsButtonY);
        clearAllSettingsNo.setPosition(clearAllSettingsNo.getPosition()[0], clearSettingsButtonY + margin*2 + b_h*2);
        clearAllSettingsYes.setPosition(clearAllSettingsYes.getPosition()[0], clearSettingsButtonY + margin*3 + b_h*3);
        
        //Update the X position for all buttons
        for (int j = 0; j < settings_cp5.getAll().size(); j++) {
            Button c = (Button) settings_cp5.getController(settings_cp5.getAll().get(j).getAddress());
            c.setPosition(c.getPosition()[0] - dx, c.getPosition()[1]);
        }

        //println("TopNav: ConfigSelector: Button Positions Updated");
    }

    void toggleVisibility() {
        isVisible = !isVisible;
        if (systemMode >= SYSTEMMODE_POSTINIT) {
            if (isVisible) {
                //the very convoluted way of locking all controllers of a single controlP5 instance...
                for (int i = 0; i < wm.widgets.size(); i++) {
                    for (int j = 0; j < wm.widgets.get(i).cp5_widget.getAll().size(); j++) {
                        wm.widgets.get(i).cp5_widget.getController(wm.widgets.get(i).cp5_widget.getAll().get(j).getAddress()).lock();
                    }
                }
                clearAllSettingsPressed = false;
            } else {
                //the very convoluted way of unlocking all controllers of a single controlP5 instance...
                for (int i = 0; i < wm.widgets.size(); i++) {
                    for (int j = 0; j < wm.widgets.get(i).cp5_widget.getAll().size(); j++) {
                        wm.widgets.get(i).cp5_widget.getController(wm.widgets.get(i).cp5_widget.getAll().get(j).getAddress()).unlock();
                    }
                }
            }
        }

        //When closed by any means and confirmation buttons are open...
        //Hide confirmation buttons and shorten height of this box
        if (clearAllSettingsPressed && !isVisible) {
            //Shorten height of this box
            h -= margin*4 + b_h*3;
            clearAllSettingsPressed = false;
        }

        updateConfigButtonPositions();
    }

    private void createExpertModeButton(String name, String text, int _x, int _y, int _w, int _h) {
        expertMode = createButton(settings_cp5, name, text, _x, _y, _w, _h, p5, 12, BUTTON_NOOBGREEN, WHITE);
        expertMode.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
                toggleVisibility();
                boolean isActive = !guiSettings.getExpertModeBoolean();
                toggleExpertModeFrontEnd(isActive);
                String outputMsg = isActive ?
                    "Expert Mode ON: All keyboard shortcuts and features are enabled!" : 
                    "Expert Mode OFF: Use spacebar to start/stop the data stream.";
                output(outputMsg);
                guiSettings.setExpertMode(isActive ? ExpertModeEnum.ON : ExpertModeEnum.OFF);
            }
        });
        expertMode.setDescription("Expert Mode enables advanced keyboard shortcuts and access to all GUI features.");
    }

    private void createSaveSettingsButton(String name, String text, int _x, int _y, int _w, int _h) {
        saveSessionSettings = createButton(settings_cp5, name, text, _x, _y, _w, _h);
        saveSessionSettings.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
                toggleVisibility();
                settings.saveButtonPressed();
            }
        });
        saveSessionSettings.setDescription("Expert Mode enables advanced keyboard shortcuts and access to all GUI features.");
    }

    private void createLoadSettingsButton(String name, String text, int _x, int _y, int _w, int _h) {
        loadSessionSettings = createButton(settings_cp5, name, text, _x, _y, _w, _h);
        loadSessionSettings.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
                toggleVisibility();
                settings.loadButtonPressed();
            }
        });
        loadSessionSettings.setDescription("Expert Mode enables advanced keyboard shortcuts and access to all GUI features.");
    }

    private void createDefaultSettingsButton(String name, String text, int _x, int _y, int _w, int _h) {
        defaultSessionSettings = createButton(settings_cp5, name, text, _x, _y, _w, _h);
        defaultSessionSettings.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
                toggleVisibility();
                settings.defaultButtonPressed();
            }
        });
        defaultSessionSettings.setDescription("Expert Mode enables advanced keyboard shortcuts and access to all GUI features.");
    }

    private void createClearAllSettingsButton(String name, String text, int _x, int _y, int _w, int _h) {
        clearAllGUISettings = createButton(settings_cp5, name, text, _x, _y, _w, _h, p5, 12, BUTTON_CAUTIONRED, WHITE);
        clearAllGUISettings.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
                //Leave box open if this button was pressed and toggle flag
                clearAllSettingsPressed = !clearAllSettingsPressed;
                //Expand or shorten height of this box
                final int delta_h = margin*4 + b_h*3;
                h += clearAllSettingsPressed ? delta_h : -delta_h;
            }
        });
        clearAllGUISettings.setDescription("This will clear all user settings and playback history. You will be asked to confirm.");
    }

    private void createClearSettingsNoButton(String name, String text, int _x, int _y, int _w, int _h) {
        clearAllSettingsNo = createButton(settings_cp5, name, text, _x, _y, _w, _h);
        clearAllSettingsNo.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
                toggleVisibility();
                //Do nothing because the user clicked Are You Sure?->No
                clearAllSettingsPressed = false;
                //Shorten height of this box
                h -= margin*4 + b_h*3;
            }
        });
    }

    private void createClearSettingsYesButton(String name, String text, int _x, int _y, int _w, int _h) {
        clearAllSettingsYes = createButton(settings_cp5, name, text, _x, _y, _w, _h);
        clearAllSettingsYes.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
                toggleVisibility();
                //Shorten height of this box
                h -= margin*4 + b_h*3;
                //User has selected Are You Sure?->Yes
                settings.clearAll();
                clearAllSettingsPressed = false;
                //Stop the system if the user clears all settings
                if (systemMode == SYSTEMMODE_POSTINIT) {
                    haltSystem();
                }
            }
        });
        clearAllSettingsYes.setDescription("Clicking 'Yes' will delete all user settings and stop the session if running.");
    }

    public void toggleExpertModeFrontEnd(boolean b) {
        if (b) {
            expertMode.getCaptionLabel().setText("Turn Expert Mode Off");
            expertMode.setColorBackground(BUTTON_EXPERTPURPLE);
        } else {
            expertMode.getCaptionLabel().setText("Turn Expert Mode On");
            expertMode.setColorBackground(BUTTON_NOOBGREEN);
        }
    } 
}

// Global Channel Selector Popup - PApplet window like FilterUI
public boolean channelSelectorPopupIsOpen = false;

class ChannelSelectorPopup extends JFrame implements MouseMotionListener, MouseListener {
    private HeadPlotElectrodes headPlot;
    private boolean[] elecVisible;
    private int headerH = 36;
    private int allBtnX, allBtnY, allBtnW = 55, allBtnH = 24;
    private int noneBtnX, noneBtnY, noneBtnW = 55, noneBtnH = 24;
    private boolean allBtnHover = false;
    private boolean noneBtnHover = false;
    private Color headerColor = new Color(57, 128, 204);
    private Color bgColor = new Color(235, 235, 235);
    private Color darkBlue = new Color(41, 89, 136);
    private Color green = new Color(76, 175, 80);
    private Color hoverColor = new Color(70, 140, 220);

    ChannelSelectorPopup() {
        super("Channels");
        setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);
        setSize(450, 450);
        setLocationRelativeTo(null);
        setResizable(true);
        setAlwaysOnTop(false);

        headPlot = new HeadPlotElectrodes(false);
        elecVisible = new boolean[32];
        for (int i = 0; i < 32; i++) elecVisible[i] = true;
        for (int i = 0; i < min(nchan, 32); i++) {
            elecVisible[i] = channelVisibility[i];
        }

        // Custom panel for drawing
        JPanel contentPane = new JPanel() {
            @Override
            protected void paintComponent(Graphics g) {
                super.paintComponent(g);
                drawContent((Graphics2D)g);
            }
        };
        contentPane.addMouseListener(this);
        contentPane.addMouseMotionListener(this);
        setContentPane(contentPane);

        addWindowListener(new java.awt.event.WindowAdapter() {
            @Override
            public void windowClosing(java.awt.event.WindowEvent e) {
                channelSelectorPopupIsOpen = false;
            }
        });

        setVisible(true);
        channelSelectorPopupIsOpen = true;
    }

    private void drawContent(Graphics2D g2) {
        int w = getWidth();
        int h = getHeight();

        // Background
        g2.setColor(bgColor);
        g2.fillRect(0, 0, w, h);

        // Header
        g2.setColor(headerColor);
        g2.fillRect(0, 0, w, headerH);

        // Title
        g2.setColor(Color.WHITE);
        g2.setFont(new Font("Arial", Font.BOLD, 14));
        g2.drawString("Channels", 12, headerH/2 + 5);

        // All button
        allBtnX = w - allBtnW * 2 - 18;
        allBtnY = (headerH - allBtnH) / 2;
        g2.setColor(allBtnHover ? hoverColor : new Color(255, 255, 255, 60));
        g2.fillRoundRect(allBtnX, allBtnY, allBtnW, allBtnH, 6, 6);
        g2.setColor(Color.WHITE);
        g2.setFont(new Font("Arial", Font.PLAIN, 11));
        FontMetrics fm = g2.getFontMetrics();
        g2.drawString("All", allBtnX + (allBtnW - fm.stringWidth("All"))/2, allBtnY + (allBtnH + fm.getAscent() - fm.getDescent())/2 - 1);

        // None button
        noneBtnX = allBtnX + allBtnW + 10;
        noneBtnY = allBtnY;
        g2.setColor(noneBtnHover ? hoverColor : new Color(255, 255, 255, 60));
        g2.fillRoundRect(noneBtnX, noneBtnY, noneBtnW, noneBtnH, 6, 6);
        g2.setColor(Color.WHITE);
        g2.drawString("None", noneBtnX + (noneBtnW - fm.stringWidth("None"))/2, noneBtnY + (noneBtnH + fm.getAscent() - fm.getDescent())/2 - 1);

        // Head plot area
        int headAreaY = headerH + 10;
        int headAreaH = h - headerH - 60;
        int cx = w / 2;
        int cy = headAreaY + headAreaH / 2;
        int r = Math.min(w, headAreaH) / 2 - 30;

        headPlot.setPosition(cx, cy, r);

        // Draw head circle
        g2.setColor(darkBlue);
        g2.setStroke(new BasicStroke(2));
        g2.drawOval(cx - r, cy - r, r * 2, r * 2);

        // Draw nose
        int[] noseX = {cx - 10, cx + 10, cx};
        int[] noseY = {cy - r + 5, cy - r + 5, cy - r - 15};
        g2.fillPolygon(noseX, noseY, 3);

        // Draw electrodes
        int elecDiam = Math.max(18, r / 6);
        int numToDraw = min(nchan, 32);
        String[] names = headPlot.getNames();
        float[][] positions = headPlot.getPositions();

        for (int i = 0; i < numToDraw; i++) {
            int ex = cx + (int)(positions[i][0] * r * 2);
            int ey = cy + (int)(positions[i][1] * r * 2);

            if (elecVisible[i]) {
                g2.setColor(green);
            } else {
                g2.setColor(new Color(180, 180, 180));
            }
            g2.setStroke(new BasicStroke(1));
            g2.setColor(darkBlue);
            g2.drawOval(ex - elecDiam/2, ey - elecDiam/2, elecDiam, elecDiam);
            if (elecVisible[i]) {
                g2.setColor(green);
            } else {
                g2.setColor(new Color(180, 180, 180));
            }
            g2.fillOval(ex - elecDiam/2 + 1, ey - elecDiam/2 + 1, elecDiam - 2, elecDiam - 2);

            // Name
            g2.setColor(elecVisible[i] ? Color.WHITE : new Color(120, 120, 120));
            g2.setFont(new Font("Arial", Font.PLAIN, 9));
            FontMetrics nfm = g2.getFontMetrics();
            g2.drawString(names[i], ex - nfm.stringWidth(names[i])/2, ey + nfm.getAscent()/2 - 1);
        }
    }

    @Override
    public void mouseMoved(MouseEvent e) {
        int mx = e.getX(), my = e.getY();
        boolean newAllHover = mx >= allBtnX && mx <= allBtnX + allBtnW && my >= allBtnY && my <= allBtnY + allBtnH;
        boolean newNoneHover = mx >= noneBtnX && mx <= noneBtnX + noneBtnW && my >= noneBtnY && my <= noneBtnY + noneBtnH;
        if (newAllHover != allBtnHover || newNoneHover != noneBtnHover) {
            allBtnHover = newAllHover;
            noneBtnHover = newNoneHover;
            repaint();
        }
    }

    @Override
    public void mousePressed(MouseEvent e) {
        int mx = e.getX(), my = e.getY();

        // Check All button
        if (mx >= allBtnX && mx <= allBtnX + allBtnW && my >= allBtnY && my <= allBtnY + allBtnH) {
            for (int i = 0; i < min(nchan, 32); i++) {
                elecVisible[i] = true;
                channelVisibility[i] = true;
            }
            syncAllWidgetChannelSelects();
            repaint();
            return;
        }

        // Check None button
        if (mx >= noneBtnX && mx <= noneBtnX + noneBtnW && my >= noneBtnY && my <= noneBtnY + noneBtnH) {
            for (int i = 0; i < min(nchan, 32); i++) {
                elecVisible[i] = false;
                channelVisibility[i] = false;
            }
            syncAllWidgetChannelSelects();
            repaint();
            return;
        }

        // Check electrode clicks
        int w = getWidth();
        int h = getHeight();
        int headAreaY = headerH + 10;
        int headAreaH = h - headerH - 60;
        int cx = w / 2;
        int cy = headAreaY + headAreaH / 2;
        int r = Math.min(w, headAreaH) / 2 - 30;
        int elecDiam = Math.max(18, r / 6);
        float[][] positions = headPlot.getPositions();

        for (int i = 0; i < min(nchan, 32); i++) {
            int ex = cx + (int)(positions[i][0] * r * 2);
            int ey = cy + (int)(positions[i][1] * r * 2);
            double dist = Math.sqrt((mx - ex) * (mx - ex) + (my - ey) * (my - ey));
            if (dist < elecDiam / 2) {
                elecVisible[i] = !elecVisible[i];
                channelVisibility[i] = elecVisible[i];
                syncAllWidgetChannelSelects();
                repaint();
                return;
            }
        }
    }

    @Override public void mouseClicked(MouseEvent e) {}
    @Override public void mouseReleased(MouseEvent e) {}
    @Override public void mouseEntered(MouseEvent e) {}
    @Override public void mouseExited(MouseEvent e) {
        if (allBtnHover || noneBtnHover) {
            allBtnHover = false;
            noneBtnHover = false;
            repaint();
        }
    }
    @Override public void mouseDragged(MouseEvent e) {}

    private void syncAllWidgetChannelSelects() {
        // Global channelVisibility is the single source of truth
        // All widgets read from channelVisibility[] directly
    }
}
