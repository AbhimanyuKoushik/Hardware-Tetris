`timescale 1ns / 1ps

module Input_Processing(
    input clk,
    input rst,
    input [5:0] btn_press_raw,
    output [5:0] btn_press_proc
);

    reg [5:0] sync1;
    reg [5:0] sync2;
    reg [18:0] debouncer_counter [0:5];
    reg [5:0] deb_state;
    reg [5:0] deb_state_prev;
    integer i;

    always @(posedge clk) begin
        for (i = 0; i < 6; i = i + 1) begin
            sync1[i] <= btn_press_raw[i];
            sync2[i] <= sync1[i];

            if (rst || sync2[i] == 0) begin
                debouncer_counter[i] <= 0;
                deb_state[i] <= 0;
            end
            else begin
                if (debouncer_counter[i] < 503500) begin
                    debouncer_counter[i] <= debouncer_counter[i] + 1;
                end
                else if (debouncer_counter[i] == 503500) begin
                    deb_state[i] <= 1;
                end
            end

            deb_state_prev[i] <= deb_state[i];
        end
    end

    assign btn_press_proc = deb_state & ~deb_state_prev;

endmodule
