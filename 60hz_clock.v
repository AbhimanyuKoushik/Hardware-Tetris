module 60hz_generator (
  input wire clk,
  input wire rst,
  output wire tick_60Hz
);

  localparam N= 25_175_000/60;
  localparam BITS = $clog2(N);
  reg [BITS-1:0] count;

  always @(posedge clk) begin
    if (rst) begin
      count <= {BITS{1'b0}};
    end else if (count== N-1) begin
      count <= {BITS{1'b0}};
    end else begin
      count <= count + 1'b1;
    end
  end

  assign tick_60Hz = (count == N-1);
endmodule  
  
  
