////////////////////////////////////////////////////////////
// HeadPlotElectrodes.pde
// Reusable head plot electrode layout component
// Used by W_HeadPlot widget and ChannelSelectorPopup
////////////////////////////////////////////////////////////

class HeadPlotElectrodes {
    private float[][] electrodeXY; // relative positions [-1, 1]
    private String[] electrodeNames;
    private int centerX, centerY, radius;
    private boolean dragEnabled;
    private int draggedIndex = -1;
    private float dragOffsetX, dragOffsetY;
    private int elecDiam;

    // Standard 10-20 electrode names for 32 channels
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

    HeadPlotElectrodes(boolean allowDrag) {
        dragEnabled = allowDrag;
        electrodeNames = ELEC_NAMES_32;
        initPositions();
    }

    private void initPositions() {
        electrodeXY = new float[32][2];
        float d = 0.12f;

        // Row 1: Fp1, Fp2
        electrodeXY[0][0] = -0.125f; electrodeXY[0][1] = -0.5f + d*(0.5f+0.2f);
        electrodeXY[1][0] = 0.125f;  electrodeXY[1][1] = electrodeXY[0][1];
        // Row 2: AF3, AF4
        electrodeXY[2][0] = -0.18f; electrodeXY[2][1] = -0.35f;
        electrodeXY[3][0] = 0.18f;  electrodeXY[3][1] = -0.35f;
        // Row 3: F7, F3, Fz, F4, F8
        electrodeXY[4][0] = -0.42f; electrodeXY[4][1] = -0.22f;
        electrodeXY[5][0] = -0.2f;  electrodeXY[5][1] = -0.22f;
        electrodeXY[6][0] = 0.0f;   electrodeXY[6][1] = -0.22f;
        electrodeXY[7][0] = 0.2f;   electrodeXY[7][1] = -0.22f;
        electrodeXY[8][0] = 0.42f;  electrodeXY[8][1] = -0.22f;
        // Row 4: FC5, FC1, FC2, FC6
        electrodeXY[9][0] = -0.33f; electrodeXY[9][1] = -0.1f;
        electrodeXY[10][0] = -0.12f; electrodeXY[10][1] = -0.1f;
        electrodeXY[11][0] = 0.12f;  electrodeXY[11][1] = -0.1f;
        electrodeXY[12][0] = 0.33f;  electrodeXY[12][1] = -0.1f;
        // Row 5: T7, C3, Cz, C4, T8
        electrodeXY[13][0] = -0.5f + d*(0.5f+0.15f); electrodeXY[13][1] = 0.0f;
        electrodeXY[14][0] = -0.2f; electrodeXY[14][1] = 0.0f;
        electrodeXY[15][0] = 0.0f;  electrodeXY[15][1] = 0.0f;
        electrodeXY[16][0] = 0.2f;  electrodeXY[16][1] = 0.0f;
        electrodeXY[17][0] = 0.5f - d*(0.5f+0.15f); electrodeXY[17][1] = 0.0f;
        // Row 6: CP5, CP1, CP2, CP6
        electrodeXY[18][0] = -0.33f; electrodeXY[18][1] = 0.1f;
        electrodeXY[19][0] = -0.12f; electrodeXY[19][1] = 0.1f;
        electrodeXY[20][0] = 0.12f;  electrodeXY[20][1] = 0.1f;
        electrodeXY[21][0] = 0.33f;  electrodeXY[21][1] = 0.1f;
        // Row 7: P7, P3, Pz, P4, P8
        electrodeXY[22][0] = -0.42f; electrodeXY[22][1] = 0.22f;
        electrodeXY[23][0] = -0.2f;  electrodeXY[23][1] = 0.22f;
        electrodeXY[24][0] = 0.0f;   electrodeXY[24][1] = 0.22f;
        electrodeXY[25][0] = 0.2f;   electrodeXY[25][1] = 0.22f;
        electrodeXY[26][0] = 0.42f;  electrodeXY[26][1] = 0.22f;
        // Row 8: PO3, POz, PO4
        electrodeXY[27][0] = -0.15f; electrodeXY[27][1] = 0.36f;
        electrodeXY[28][0] = 0.0f;   electrodeXY[28][1] = 0.36f;
        electrodeXY[29][0] = 0.15f;  electrodeXY[29][1] = 0.36f;
        // Row 9: O1, O2
        electrodeXY[30][0] = -0.125f; electrodeXY[30][1] = 0.5f - d*(0.5f+0.2f);
        electrodeXY[31][0] = 0.125f;  electrodeXY[31][1] = electrodeXY[30][1];
    }

    public void setPosition(int cx, int cy, int r) {
        centerX = cx;
        centerY = cy;
        radius = r;
        elecDiam = max(20, radius / 6);
    }

    public int getElecDiam() {
        return elecDiam;
    }

    public int getNumElectrodes() {
        return 32;
    }

    public float[][] getPositions() {
        return electrodeXY;
    }

    public String[] getNames() {
        return electrodeNames;
    }

    // Get pixel position of electrode
    public int[] getPixelPos(int index) {
        int px = centerX + (int)(electrodeXY[index][0] * radius * 2);
        int py = centerY + (int)(electrodeXY[index][1] * radius * 2);
        return new int[]{px, py};
    }

    // Draw head outline (circle + nose)
    public void drawHeadOutline() {
        // Head circle
        noFill();
        stroke(OPENBCI_DARKBLUE);
        strokeWeight(2);
        ellipse(centerX, centerY, radius * 2, radius * 2);

        // Nose
        fill(OPENBCI_DARKBLUE);
        noStroke();
        triangle(centerX - 10, centerY - radius + 5,
                 centerX + 10, centerY - radius + 5,
                 centerX, centerY - radius - 15);
    }

    // Draw all electrodes with visibility states
    public void drawElectrodes(boolean[] visible, boolean showNames) {
        for (int i = 0; i < 32; i++) {
            int[] pos = getPixelPos(i);
            boolean isVisible = (visible != null && i < visible.length) ? visible[i] : true;

            // Electrode circle
            if (isVisible) {
                fill(TURN_ON_GREEN);
            } else {
                fill(180);
            }
            stroke(OPENBCI_DARKBLUE);
            strokeWeight(1);
            ellipse(pos[0], pos[1], elecDiam, elecDiam);
        }
    }

    // Draw electrodes with custom colors (for HeadPlot widget)
    public void drawElectrodesWithColors(int[][] rgb, boolean[] visible) {
        for (int i = 0; i < 32; i++) {
            int[] pos = getPixelPos(i);
            boolean isVisible = (visible == null || i >= visible.length || visible[i]);

            if (!isVisible) continue;

            // Electrode circle with custom color
            fill(rgb[0][i], rgb[1][i], rgb[2][i]);
            stroke(OPENBCI_DARKBLUE);
            strokeWeight(1);
            ellipse(pos[0], pos[1], elecDiam, elecDiam);
        }
    }

    // Draw electrode names separately (call after drawElectrodes)
    public void drawElectrodeNames(boolean[] visible) {
        for (int i = 0; i < 32; i++) {
            boolean isVisible = (visible != null && i < visible.length) ? visible[i] : true;
            if (!isVisible) continue;

            int[] pos = getPixelPos(i);
            fill(WHITE);
            noStroke();
            textSize(9);
            textAlign(CENTER, CENTER);
            text(electrodeNames[i], pos[0], pos[1]);
        }
    }

    // Handle mouse press - returns clicked electrode index or -1
    public int mousePressed() {
        if (!dragEnabled) {
            // Simple click detection
            for (int i = 0; i < 32; i++) {
                int[] pos = getPixelPos(i);
                float dist = sqrt((mouseX - pos[0]) * (mouseX - pos[0]) + (mouseY - pos[1]) * (mouseY - pos[1]));
                if (dist < elecDiam / 2) {
                    return i;
                }
            }
            return -1;
        }

        // Drag mode
        for (int i = 0; i < 32; i++) {
            int[] pos = getPixelPos(i);
            float dist = sqrt((mouseX - pos[0]) * (mouseX - pos[0]) + (mouseY - pos[1]) * (mouseY - pos[1]));
            if (dist < elecDiam / 2) {
                draggedIndex = i;
                dragOffsetX = mouseX - pos[0];
                dragOffsetY = mouseY - pos[1];
                return i;
            }
        }
        draggedIndex = -1;
        return -1;
    }

    // Handle mouse drag
    public void mouseDragged() {
        if (!dragEnabled || draggedIndex < 0) return;

        int pixelX = mouseX - (int)dragOffsetX;
        int pixelY = mouseY - (int)dragOffsetY;

        // Convert back to relative coordinates
        float relX = (float)(pixelX - centerX) / (radius * 2);
        float relY = (float)(pixelY - centerY) / (radius * 2);

        // Clamp to head circle
        float dist = sqrt(relX * relX + relY * relY);
        if (dist > 0.9f) {
            relX = relX / dist * 0.9f;
            relY = relY / dist * 0.9f;
        }

        electrodeXY[draggedIndex][0] = relX;
        electrodeXY[draggedIndex][1] = relY;
    }

    // Handle mouse release
    public void mouseReleased() {
        draggedIndex = -1;
    }

    // Check if mouse is over any electrode
    public boolean isMouseOverAny() {
        for (int i = 0; i < 32; i++) {
            int[] pos = getPixelPos(i);
            float dist = sqrt((mouseX - pos[0]) * (mouseX - pos[0]) + (mouseY - pos[1]) * (mouseY - pos[1]));
            if (dist < elecDiam / 2) return true;
        }
        return false;
    }

    // Get electrode positions in pixel coordinates
    public float[][] getPixelPositions() {
        float[][] pixPos = new float[32][2];
        for (int i = 0; i < 32; i++) {
            pixPos[i][0] = centerX + electrodeXY[i][0] * radius * 2;
            pixPos[i][1] = centerY + electrodeXY[i][1] * radius * 2;
        }
        return pixPos;
    }
}
