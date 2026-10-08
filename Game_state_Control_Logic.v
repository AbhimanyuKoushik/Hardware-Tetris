module Game_state_Control_Logic(
    input              clk,
    input              rst,
    input      [4:0]   btn_press_proc,
    input              tick_60Hz,
    input      [2:0]   active_piece,
    input      [199:0] grid_state,
    output reg [3:0]   active_X,
    output reg [4:0]   active_Y,
    output reg [1:0]   rotation_state,
    output reg         spawn_pulse,
    output reg         write_en,
    output reg [7:0]   write_addr,
    output reg         write_data
);
    localparam MOVE        = 3'd0,
               LOCK        = 3'd1,
               SPAWN       = 3'd2,
               LOCK_DELAY  = 3'd3,
               GAME_OVER   = 3'd4,
               SPAWN_WAIT  = 3'd5,
               SPAWN_CHECK = 3'd6;
    reg [2:0] state;
    reg [1:0] cell_idx;
    localparam GRAVITY_TICKS    = 30;
    localparam LOCK_DELAY_TICKS = 30;
    reg [5:0] tick_count;
    reg [5:0] lock_delay_count;
    reg       fall_due;
    wire [3:0] tentative_X_left   = active_X - 4'd1;
    wire [3:0] tentative_X_right  = active_X + 4'd1;
    wire [1:0] tentative_rotation = rotation_state + 2'd1;
    wire [4:0] gravity_Y          = active_Y + 5'd1;
    wire [3:0] tentative_X_SRS;
    wire [4:0] tentative_Y_SRS;
    wire collide_left, collide_right, collide_rotation;
    wire collision_due_to_gravity, collide_spawn;
    collision_check check_left (
        .X(tentative_X_left), .Y(active_Y), .rotation_state(rotation_state),
        .active_piece(active_piece), .grid_state(grid_state), .collision(collide_left));
    collision_check check_right (
        .X(tentative_X_right), .Y(active_Y), .rotation_state(rotation_state),
        .active_piece(active_piece), .grid_state(grid_state), .collision(collide_right));
    collision_check check_gravity (
        .X(active_X), .Y(gravity_Y), .rotation_state(rotation_state),
        .active_piece(active_piece), .grid_state(grid_state), .collision(collision_due_to_gravity));
    collision_check check_spawn (
        .X(4'd4), .Y(5'd1), .rotation_state(2'b00),
        .active_piece(active_piece), .grid_state(grid_state), .collision(collide_spawn));
    Super_rotation_system srs_inst (
        .rotation_state(rotation_state),
        .active_piece(active_piece),
        .active_X(active_X),
        .active_Y(active_Y),
        .grid_state(grid_state),
        .collision(collide_rotation),
        .tentative_X(tentative_X_SRS),
        .tentative_Y(tentative_Y_SRS));
    wire [20:1] hard_drop_collisions;
    wire [20:1] drop_hit;
    reg  [4:0]  final_drop_Y;
    reg         found;
    genvar k;
    generate
        for (k = 1; k <= 20; k = k + 1) begin : drop_checkers
            wire [5:0] sum = active_Y + k;
            collision_check check_inst (
                .X(active_X), .Y(sum[4:0]), .rotation_state(rotation_state),
                .active_piece(active_piece), .grid_state(grid_state),
                .collision(hard_drop_collisions[k]));
            assign drop_hit[k] = hard_drop_collisions[k] | (sum > 6'd19);
        end
    endgenerate
    integer i;
    always @(*) begin
        final_drop_Y = active_Y;
        found        = 1'b0;
        for (i = 1; i <= 20; i = i + 1) begin
            if (!found && drop_hit[i]) begin
                found        = 1'b1;
                final_drop_Y = active_Y + i[4:0] - 5'd1;
            end
        end
    end
    wire [3:0] lx_A, lx_1, lx_2, lx_3;
    wire [4:0] ly_A, ly_1, ly_2, ly_3;
    shape_look_up_table lock_lut (
        .rotation_state(rotation_state), .active_X(active_X), .active_Y(active_Y),
        .active_piece(active_piece),
        .x_A(lx_A), .x_1(lx_1), .x_2(lx_2), .x_3(lx_3),
        .y_A(ly_A), .y_1(ly_1), .y_2(ly_2), .y_3(ly_3));
    reg [3:0] lock_x;
    reg [4:0] lock_y;
    always @(*) begin
        case (cell_idx)
            2'd0:    begin lock_x = lx_A; lock_y = ly_A; end
            2'd1:    begin lock_x = lx_1; lock_y = ly_1; end
            2'd2:    begin lock_x = lx_2; lock_y = ly_2; end
            default: begin lock_x = lx_3; lock_y = ly_3; end
        endcase
    end
    wire [7:0] lock_addr = lock_y * 8'd10 + lock_x;
    always @(posedge clk) begin
        write_en    <= 1'b0;
        spawn_pulse <= 1'b0;
        if (rst) begin
            state            <= SPAWN;
            active_X         <= 4'd4;
            active_Y         <= 5'd1;
            rotation_state   <= 2'b00;
            cell_idx         <= 2'd0;
            tick_count       <= 6'd0;
            lock_delay_count <= 6'd0;
            fall_due         <= 1'b0;
            write_addr       <= 8'd0;
            write_data       <= 1'b0;
        end
        else case (state)
            MOVE: begin
				     if (btn_press_proc[4]) begin
                    active_Y <= final_drop_Y;
                    cell_idx <= 2'd0;
                    state    <= LOCK_DELAY;
                end
                else if (btn_press_proc[3]) begin
                    if (!collide_left) active_X <= tentative_X_left;
                end
                else if (btn_press_proc[2]) begin
                    if (!collide_right) active_X <= tentative_X_right;
                end
                else if (btn_press_proc[1]) begin
                    if (!collide_rotation) begin
                        rotation_state <= tentative_rotation;
                        active_X       <= tentative_X_SRS;
                        active_Y       <= tentative_Y_SRS;
                    end
                end
                else if (btn_press_proc[0]) begin
                    active_Y <= final_drop_Y;
                    cell_idx <= 2'd0;
                    state    <= LOCK;
                end
                else if (fall_due) begin
                    fall_due <= 1'b0;
                    if (!collision_due_to_gravity) active_Y <= gravity_Y;
                    else begin
                        lock_delay_count <= 6'd0;
                        state            <= LOCK_DELAY;
                    end
                end
                if (tick_60Hz) begin
                    if (tick_count == GRAVITY_TICKS - 1) begin
                        tick_count <= 6'd0;
                        fall_due   <= 1'b1;
                    end
                    else tick_count <= tick_count + 6'd1;
                end
            end
            LOCK_DELAY: begin
                if (tick_60Hz) lock_delay_count <= lock_delay_count + 6'd1;
                if (btn_press_proc[3] && !collide_left) begin
                    active_X         <= tentative_X_left;
                    lock_delay_count <= 6'd0;
                end
                else if (btn_press_proc[2] && !collide_right) begin
                    active_X         <= tentative_X_right;
                    lock_delay_count <= 6'd0;
                end
                else if (btn_press_proc[1] && !collide_rotation) begin
                    rotation_state   <= tentative_rotation;
                    active_X         <= tentative_X_SRS;
                    active_Y         <= tentative_Y_SRS;
                    lock_delay_count <= 6'd0;
                end
                else if (btn_press_proc[4]) begin
                    active_Y <= final_drop_Y;
                    cell_idx <= 2'd0;
                    state    <= LOCK;
                end
                else if (lock_delay_count >= LOCK_DELAY_TICKS) begin
                    cell_idx <= 2'd0;
                    state    <= LOCK;
                end
                else if (!collision_due_to_gravity) begin
                    tick_count <= 6'd0;
                    fall_due   <= 1'b0;
                    state      <= MOVE;
                end
            end
            LOCK: begin
                write_en   <= 1'b1;
                write_addr <= lock_addr;
                write_data <= 1'b1;
                if (cell_idx == 2'd3) state <= SPAWN;
                else                  cell_idx <= cell_idx + 2'd1;
            end
            SPAWN: begin
                active_X         <= 4'd4;
                active_Y         <= 5'd1;
                rotation_state   <= 2'b00;
                tick_count       <= 6'd0;
                fall_due         <= 1'b0;
                lock_delay_count <= 6'd0;
                spawn_pulse      <= 1'b1;
                state            <= SPAWN_WAIT;
            end
            SPAWN_WAIT: begin
                state <= SPAWN_CHECK;
            end
            SPAWN_CHECK: begin
                if (collide_spawn) state <= GAME_OVER;
                else               state <= MOVE;
            end
            GAME_OVER: begin
                state <= GAME_OVER;
            end
            default: state <= SPAWN;
        endcase
    end
endmodule
module collision_check(
    input  [3:0]   X,
    input  [4:0]   Y,
    input  [1:0]   rotation_state,
    input  [2:0]   active_piece,
    input  [199:0] grid_state,
    output         collision
);
    wire [3:0] subA_x, sub1_x, sub2_x, sub3_x;
    wire [4:0] subA_y, sub1_y, sub2_y, sub3_y;
    shape_look_up_table lut_inst (
        .rotation_state (rotation_state),
        .active_X       (X),
        .active_Y       (Y),
        .active_piece   (active_piece),
        .x_A(subA_x), .x_1(sub1_x), .x_2(sub2_x), .x_3(sub3_x),
        .y_A(subA_y), .y_1(sub1_y), .y_2(sub2_y), .y_3(sub3_y)
    );
    wire valid_A = (subA_x <= 4'd9) && (subA_y <= 5'd19);
    wire valid_1 = (sub1_x <= 4'd9) && (sub1_y <= 5'd19);
    wire valid_2 = (sub2_x <= 4'd9) && (sub2_y <= 5'd19);
    wire valid_3 = (sub3_x <= 4'd9) && (sub3_y <= 5'd19);
    wire [8:0] idx_A = subA_y * 9'd10 + subA_x;
    wire [8:0] idx_1 = sub1_y * 9'd10 + sub1_x;
    wire [8:0] idx_2 = sub2_y * 9'd10 + sub2_x;
    wire [8:0] idx_3 = sub3_y * 9'd10 + sub3_x;
    wire occ_A = valid_A ? grid_state[idx_A] : 1'b0;
    wire occ_1 = valid_1 ? grid_state[idx_1] : 1'b0;
    wire occ_2 = valid_2 ? grid_state[idx_2] : 1'b0;
    wire occ_3 = valid_3 ? grid_state[idx_3] : 1'b0;
    assign collision = !valid_A || !valid_1 || !valid_2 || !valid_3 ||
                       occ_A   || occ_1   || occ_2   || occ_3;
endmodule
module shape_look_up_table(
    input  [1:0] rotation_state,
    input  [3:0] active_X,
    input  [4:0] active_Y,
    input  [2:0] active_piece,
    output reg [3:0] x_A, x_1, x_2, x_3,
    output reg [4:0] y_A, y_1, y_2, y_3
);
    always @(*) begin
        x_A = active_X; y_A = active_Y;
        x_1 = active_X; y_1 = active_Y;
        x_2 = active_X; y_2 = active_Y;
        x_3 = active_X; y_3 = active_Y;
        case (active_piece)
            3'b001: begin
                x_1 = active_X + 1; y_1 = active_Y;
                x_2 = active_X + 1; y_2 = active_Y + 1;
                x_3 = active_X;     y_3 = active_Y + 1;
            end
            3'b010: begin
                case (rotation_state)
                    2'b00: begin x_1=active_X-1; y_1=active_Y;   x_2=active_X+1; y_2=active_Y;   x_3=active_X+2; y_3=active_Y;   end
                    2'b01: begin x_1=active_X;   y_1=active_Y-1; x_2=active_X;   y_2=active_Y+1; x_3=active_X;   y_3=active_Y+2; end
                    2'b10: begin x_1=active_X+1; y_1=active_Y;   x_2=active_X-1; y_2=active_Y;   x_3=active_X-2; y_3=active_Y;   end
                    2'b11: begin x_1=active_X;   y_1=active_Y+1; x_2=active_X;   y_2=active_Y-1; x_3=active_X;   y_3=active_Y-2; end
                endcase
            end
            3'b011: begin
                case (rotation_state)
                    2'b00: begin x_1=active_X+1; y_1=active_Y;   x_2=active_X-1; y_2=active_Y;   x_3=active_X;   y_3=active_Y-1; end
                    2'b01: begin x_1=active_X;   y_1=active_Y+1; x_2=active_X;   y_2=active_Y-1; x_3=active_X+1; y_3=active_Y;   end
                    2'b10: begin x_1=active_X-1; y_1=active_Y;   x_2=active_X+1; y_2=active_Y;   x_3=active_X;   y_3=active_Y+1; end
                    2'b11: begin x_1=active_X;   y_1=active_Y-1; x_2=active_X;   y_2=active_Y+1; x_3=active_X-1; y_3=active_Y;   end
                endcase
            end
            3'b100: begin
                case (rotation_state)
                    2'b00: begin x_1=active_X-1; y_1=active_Y;   x_2=active_X+1; y_2=active_Y;   x_3=active_X+1; y_3=active_Y-1; end
                    2'b01: begin x_1=active_X;   y_1=active_Y-1; x_2=active_X;   y_2=active_Y+1; x_3=active_X+1; y_3=active_Y+1; end
                    2'b10: begin x_1=active_X+1; y_1=active_Y;   x_2=active_X-1; y_2=active_Y;   x_3=active_X-1; y_3=active_Y+1; end
                    2'b11: begin x_1=active_X;   y_1=active_Y+1; x_2=active_X;   y_2=active_Y-1; x_3=active_X-1; y_3=active_Y-1; end
                endcase
            end
            3'b101: begin
                case (rotation_state)
                    2'b00: begin x_1=active_X+1; y_1=active_Y;   x_2=active_X-1; y_2=active_Y;   x_3=active_X-1; y_3=active_Y-1; end
                    2'b01: begin x_1=active_X;   y_1=active_Y+1; x_2=active_X;   y_2=active_Y-1; x_3=active_X+1; y_3=active_Y-1; end
                    2'b10: begin x_1=active_X-1; y_1=active_Y;   x_2=active_X+1; y_2=active_Y;   x_3=active_X+1; y_3=active_Y+1; end
                    2'b11: begin x_1=active_X;   y_1=active_Y-1; x_2=active_X;   y_2=active_Y+1; x_3=active_X-1; y_3=active_Y+1; end
                endcase
            end
            3'b110: begin
                case (rotation_state)
                    2'b00: begin x_1=active_X+1; y_1=active_Y-1; x_2=active_X;   y_2=active_Y-1; x_3=active_X-1; y_3=active_Y;   end
                    2'b01: begin x_1=active_X+1; y_1=active_Y+1; x_2=active_X+1; y_2=active_Y;   x_3=active_X;   y_3=active_Y-1; end
                    2'b10: begin x_1=active_X-1; y_1=active_Y+1; x_2=active_X;   y_2=active_Y+1; x_3=active_X+1; y_3=active_Y;   end
                    2'b11: begin x_1=active_X-1; y_1=active_Y-1; x_2=active_X-1; y_2=active_Y;   x_3=active_X;   y_3=active_Y+1; end
                endcase
            end
            3'b111: begin
                case (rotation_state)
                    2'b00: begin x_1=active_X+1; y_1=active_Y;   x_2=active_X;   y_2=active_Y-1; x_3=active_X-1; y_3=active_Y-1; end
                    2'b01: begin x_1=active_X;   y_1=active_Y+1; x_2=active_X+1; y_2=active_Y;   x_3=active_X+1; y_3=active_Y-1; end
                    2'b10: begin x_1=active_X-1; y_1=active_Y;   x_2=active_X;   y_2=active_Y+1; x_3=active_X+1; y_3=active_Y+1; end
                    2'b11: begin x_1=active_X;   y_1=active_Y-1; x_2=active_X-1; y_2=active_Y;   x_3=active_X-1; y_3=active_Y+1; end
                endcase
            end
            default: ;
        endcase
    end
endmodule
module Super_rotation_system(
    input  [1:0]   rotation_state,
    input  [2:0]   active_piece,
    input  [3:0]   active_X,
    input  [4:0]   active_Y,
    input  [199:0] grid_state,
    output reg        collision,
    output reg [3:0]  tentative_X,
    output reg [4:0]  tentative_Y
);
    wire [1:0] new_rot = rotation_state + 2'd1;
    wire       is_I    = (active_piece == 3'b010);
    function [7:0] kick;
        input       is_i;
        input [1:0] rs;
        input [2:0] test;
        reg signed [3:0] k;
        reg signed [3:0] l;
        begin
            k = 4'sd0;
            l = 4'sd0;
            if (!is_i) begin
                case (test)
                    1: begin k =  0; l =  0; end
                    2: begin
                        k = (rs % 3 == 0) ? -1 : 1;
                        l = 0;
                    end
                    3: begin
                        k = (rs % 3 == 0) ? -1 : 1;
                        l = (rs % 2 == 0) ? -1 : 1;
                    end
                    4: begin
                        k = 0;
                        l = (rs % 2 == 0) ? 2 : -2;
                    end
                    5: begin
                        k = (rs % 3 == 0) ? -1 : 1;
                        l = (rs % 2 == 0) ? 2 : -2;
                    end
                    default: begin k = 0; l = 0; end
                endcase
            end
            else begin
                case (rs)
                    2'b00: begin
                        case (test)
                            1: begin k =  1; l =  0; end
                            2: begin k = -1; l =  0; end
                            3: begin k =  2; l =  0; end
                            4: begin k = -1; l =  1; end
                            5: begin k =  2; l = -2; end
                            default: begin k = 0; l = 0; end
                        endcase
                    end
                    2'b01: begin
                        case (test)
                            1: begin k =  0; l =  1; end
                            2: begin k = -1; l =  1; end
                            3: begin k =  2; l =  1; end
                            4: begin k = -1; l = -1; end
                            5: begin k =  2; l =  2; end
                            default: begin k = 0; l = 0; end
                        endcase
                    end
                    2'b10: begin
                        case (test)
                            1: begin k = -1; l =  0; end
                            2: begin k =  1; l =  0; end
                            3: begin k = -2; l =  0; end
                            4: begin k =  1; l = -1; end
                            5: begin k = -2; l =  2; end
                            default: begin k = 0; l = 0; end
                        endcase
                    end
                    2'b11: begin
                        case (test)
                            1: begin k =  0; l = -1; end
                            2: begin k =  1; l = -1; end
                            3: begin k = -2; l = -1; end
                            4: begin k =  1; l =  1; end
                            5: begin k = -2; l = -2; end
                            default: begin k = 0; l = 0; end
                        endcase
                    end
                endcase
            end
            kick = {k, l};
        end
    endfunction
    wire [19:0] cand_x;
    wire [24:0] cand_y;
    wire [4:0]  kick_collide;
    genvar t;
    generate
        for (t = 0; t < 5; t = t + 1) begin : kick_tests
            wire [7:0] kk = kick(is_I, rotation_state, t[2:0] + 3'd1);
            wire [3:0] dx = kk[7:4];
            wire [3:0] dy = kk[3:0];
            assign cand_x[4*t +: 4] = active_X + dx;
            assign cand_y[5*t +: 5] = active_Y + {dy[3], dy};
            collision_check cc (
                .X(cand_x[4*t +: 4]),
                .Y(cand_y[5*t +: 5]),
                .rotation_state(new_rot),
                .active_piece(active_piece),
                .grid_state(grid_state),
                .collision(kick_collide[t]));
        end
    endgenerate
    integer j;
    always @(*) begin
        collision   = 1'b1;
        tentative_X = active_X;
        tentative_Y = active_Y;
        for (j = 4; j >= 0; j = j - 1) begin
            if (!kick_collide[j]) begin
                collision   = 1'b0;
                tentative_X = cand_x[4*j +: 4];
                tentative_Y = cand_y[5*j +: 5];
            end
        end
    end
endmodule
