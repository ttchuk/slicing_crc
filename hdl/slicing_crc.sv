// MIT License

// Copyright (c) 2023 Tom Chisholm

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

`timescale 1ns/1ps

module slicing_crc #(
    parameter SLICE_LENGTH = 8,
    parameter INITIAL_CRC = 32'hFFFFFFFF,
    parameter INVERT_OUTPUT = 1,
    parameter REGISTER_OUTPUT = 1
) (
    input wire clk,
    input wire reset,
    input wire [8*SLICE_LENGTH-1:0] data,
    input wire [SLICE_LENGTH-1:0] valid,
    output wire [31:0] crc
);

    // Read CRC lookup tables
    logic [31:0] crc_tables [SLICE_LENGTH][256];
    initial begin
        $readmemh("crc_tables.mem", crc_tables); //todo check dimensions
    end

    // Find number of bytes valid in this cycle
    logic [$clog2(SLICE_LENGTH):0] num_input_bytes;
    wire any_valid;

    always @(*) begin
        num_input_bytes = 0;
        for (int i = 0; i < SLICE_LENGTH; i++) begin
            if (valid[i]) begin
                num_input_bytes = i + 1;
            end
        end
    end

    assign any_valid = num_input_bytes != 0;


    // CRC storage
    logic [31:0] prev_crc, crc_calc, crc_out;
    
    initial prev_crc <= INITIAL_CRC;

    always @(posedge clk)
    if (reset) begin
        prev_crc <= INITIAL_CRC;
    end else if (any_valid) begin
        prev_crc <= crc_calc;
    end

    // Table lookups
    wire [31:0] table_outs [SLICE_LENGTH];
    genvar gi;
    generate for (gi = 0; gi < SLICE_LENGTH; gi++) begin
        wire [7:0] table_lookup;
        wire [31:0] table_out;

        assign table_lookup = (gi < 4) ? data[8*gi +: 8] ^ prev_crc[8*gi +: 8] : data[8*gi +: 8];
        assign table_out = crc_tables[num_input_bytes - gi - 1][table_lookup]; // Note table[0] is for last (ms) byte
        assign table_outs[gi] = table_out; // Keep both for debugging 
    end endgenerate

    // Final CRC calculation
    always @(*) begin
        crc_calc = 0;
        for (int i = 0; i < SLICE_LENGTH; i++) 
        if (valid[i]) begin
            crc_calc = crc_calc ^ table_outs[i];
        end

        crc_calc = crc_calc ^ prev_crc >> (8*num_input_bytes); // If slice length < 4, need to xor in the remaining bytes of previous crc
    end

    // CRC output
    assign crc_out = REGISTER_OUTPUT ? prev_crc : crc_calc;
    assign crc = INVERT_OUTPUT ? ~crc_out : crc_out;

endmodule