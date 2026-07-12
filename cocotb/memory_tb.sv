`timescale 1ns/1ps

// =============================================================================
// Main Testbench Module
// =============================================================================
module memory_tb;

    logic       clk;
    logic       rst_n;
    logic [7:0] write_data;
    logic [6:0] write_addr;
    logic       write_en;
    logic [6:0] read_addr;
    logic       read_en;
    logic [7:0] read_data;
    logic       swap;

    int error_count = 0;
    logic check_sram0 = 0;
    logic check_sram1 = 0;

    // Dedicated tracking counter to eliminate address subtraction math
    logic [6:0] check_addr = 0;
    logic [7:0] expected_data;

    // Instantiate Device Under Test (DUT)
    memory dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .write_data (write_data),
        .write_addr (write_addr),
        .write_en   (write_en),
        .read_addr  (read_addr),
        .read_en    (read_en),
        .read_data  (read_data),
        .swap       (swap)
    );

    // Clock Generation (100MHz)
    always #5 clk = (clk === 1'b0) ? 1'b1 : 1'b0;

    // File Dumping for GTKWave
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, memory_tb);
    end

    // -------------------------------------------------------------------------
    // Independent Checking Monitors 
    // -------------------------------------------------------------------------
    // Monitor SRAM_0 Reads (Phase 2 - verification after state change)
    always @(negedge clk) begin
        if (check_sram0) begin
            expected_data = check_addr + 8'hA0;
            if (read_data !== expected_data) begin
                $display("[ERROR] SRAM_0 mismatch at Tracking Index %0d! Expected: %h, Got: %h", check_addr, expected_data, read_data);
                error_count++;
            end
            check_addr++;
        end
    end

    // Monitor SRAM_1 Reads (Phase 3 - verification after state change)
    always @(negedge clk) begin
        if (check_sram1) begin
            expected_data = check_addr + 8'h50;
            if (read_data !== expected_data) begin
                $display("[ERROR] SRAM_1 mismatch at Tracking Index %0d! Expected: %h, Got: %h", check_addr, expected_data, read_data);
                error_count++;
            end
            check_addr++;
        end
    end

    // -------------------------------------------------------------------------
    // Main Stimulus Generation
    // -------------------------------------------------------------------------
    initial begin
        clk        = 0;
        rst_n      = 0;
        write_data = 0;
        write_addr = 0;
        write_en   = 0;
        read_addr  = 0;
        read_en    = 0;
        swap       = 0;

        // 1. Reset Phase
        #20;
        rst_n = 1;
        #10;
        $display("[TB INFO] --- Starting Ping-Pong Buffer Verification ---");

        // 2. Phase 1: Write to SRAM_0 (State = 0)
        $display("[TB INFO] Phase 1: Writing unique pattern to SRAM_0...");
        for (int i = 0; i < 128; i++) begin
            @(posedge clk);
            write_addr = i;
            write_data = i + 8'hA0;
            write_en   = 1;
        end
        @(posedge clk);
        write_en = 0;

        // 3. Trigger Swap
        $display("[TB INFO] Triggering SWAP...");
        @(posedge clk);
        swap = 1;
        @(posedge clk);
        swap = 0;

        // 4. Phase 2: Concurrent Read (SRAM_0) and Write (SRAM_1)
        $display("[TB INFO] Phase 2: Executing simultaneous pipelined Read/Write...");
        check_addr = 0; // Reset tracking pointer
        
        for (int i = 0; i < 128; i++) begin
            write_addr = i;
            write_data = i + 8'h50;
            write_en   = 1;

            read_addr  = i;
            read_en    = 1;

            // Turn on checker exactly 1 cycle later to absorb synchronous SRAM read latency
            if (i == 1) check_sram0 = 1;
            @(posedge clk);
        end
        // --- FIX: Hold control signals for 1 extra cycle to capture the 127th read ---
        @(posedge clk); 
        write_en    = 0;
        read_en     = 0;
        check_sram0 = 0;

        // 5. Trigger Second Swap
        $display("[TB INFO] Triggering Second SWAP...");
        @(posedge clk);
        swap = 1;
        @(posedge clk);
        swap = 0;

        // 6. Phase 3: Read back from SRAM_1 and verify
        $display("[TB INFO] Phase 3: Verifying concurrent writes landed safely in SRAM_1...");
        check_addr = 0; // Reset tracking pointer again
        
        for (int i = 0; i < 128; i++) begin
            read_addr = i;
            read_en   = 1;
            if (i == 1) check_sram1 = 1;
            @(posedge clk);
        end
        // --- FIX: Hold control signals for 1 extra cycle to capture the 127th read ---
        @(posedge clk);
        read_en     = 0;
        check_sram1 = 0;

        #50;
        $display("-----------------------------------------------------");
        if (error_count == 0) begin
            $display(" STATUS: PASSED! Ping-pong isolation is working perfectly.");
        end else begin
            $display(" STATUS: FAILED! Found %0d data mismatches.", error_count);
        end
        $display("-----------------------------------------------------");
        $finish;
    end

endmodule
