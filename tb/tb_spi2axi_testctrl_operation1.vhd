-------------------------------------------------------------------------------
--
--  SPI to AXI4-Lite Bridge, test controller entity declaration 
--
--  Description:  
--    TODO 
--
--  Author(s):
--    Guy Eschemann, guy@airhdl.com
--
-------------------------------------------------------------------------------
--
-- Copyright (c) 2022 Guy Eschemann
-- 
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
-- 
--     http://www.apache.org/licenses/LICENSE-2.0
-- 
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library OSVVM;
context OSVVM.OsvvmContext;
use osvvm.ScoreboardPkg_slv.all;

architecture operation1 of tb_spi2axi_testctrl is

    -------------------------------------------------------------------------------
    -- Signals
    -------------------------------------------------------------------------------

    signal TestDone : integer_barrier := 1;

    -------------------------------------------------------------------------------
    -- Aliases
    -------------------------------------------------------------------------------

    alias TxBurstFifo : ScoreboardIdType is SpiRec.BurstFifo;
    alias RxBurstFifo : ScoreboardIdType is SpiRec.BurstFifo;

begin

    ------------------------------------------------------------
    -- ControlProc
    --   Set up AlertLog and wait for end of test
    ------------------------------------------------------------
    ControlProc : process
        variable addr            : unsigned(31 downto 0);
        variable wdata           : std_logic_vector(31 downto 0);
        variable rdata           : std_logic_vector(31 downto 0);
        variable value           : natural;
        variable spi_tx_bytes    : integer_vector(0 to 10);
        variable spi_tx_byte_idx : natural;
        variable mem_reg         : std_logic_vector(31 downto 0);
        variable num_bytes       : integer;
        variable valid           : boolean;
        variable rx_byte         : std_logic_vector(7 downto 0);
        variable bytes_to_send   : integer;
    begin
        -- Initialization of test
        SetAlertLogName("tb_spi2axi_operation1");
        SetLogEnable(INFO, TRUE);
        SetLogEnable(DEBUG, TRUE);
        SetLogEnable(PASSED, TRUE);     -- Enable PASSED logs

        -- Wait for testbench initialization 
        wait for 0 ns;
        wait for 0 ns;
        --TranscriptOpen(OSVVM_RESULTS_DIR & "tb_spi2axi_operation1.txt");

        -- Wait for Design Reset
        wait until nReset = '1';
        ClearAlerts;

        Log("Testing SPI register write");
        spi_tx_byte_idx               := 0;
        spi_tx_bytes(spi_tx_byte_idx) := 0; -- 0x00 -> SPI write
        spi_tx_byte_idx               := spi_tx_byte_idx + 1;
        addr                          := x"76543210";
        wdata                         := x"12345678";
        Log("SPI WR: addr = 0x" & to_hxstring(addr) & ", data = 0x" & to_hxstring(wdata));
        for i in 3 downto 0 loop
            spi_tx_bytes(spi_tx_byte_idx) := to_integer(addr(i * 8 + 7 downto i * 8));
            spi_tx_byte_idx               := spi_tx_byte_idx + 1;
        end loop;
        for i in 3 downto 0 loop
            spi_tx_bytes(spi_tx_byte_idx) := to_integer(unsigned(wdata(i * 8 + 7 downto i * 8)));
            spi_tx_byte_idx               := spi_tx_byte_idx + 1;
        end loop;
        spi_tx_bytes(spi_tx_byte_idx) := 0; -- a dummy byte to allow writing the data word
        spi_tx_byte_idx               := spi_tx_byte_idx + 1;
        spi_tx_bytes(spi_tx_byte_idx) := 0; -- AXI4 write response
        spi_tx_byte_idx               := spi_tx_byte_idx + 1;
        PushBurst(TxBurstFifo, spi_tx_bytes, 8);
        SendBurst(SpiRec, spi_tx_byte_idx);

        wait for 100 us;

        -- Get received data
        GetBurst(SpiRec, num_bytes);
        AffirmIfEqual(num_bytes, 11);
        for i in 0 to num_bytes - 1 loop
            PopWord(RxBurstFifo, valid, rx_byte, bytes_to_send);
            AlertIfNot(valid, "invalid receive data");
            Log("RX byte: " & to_string(rx_byte));
        end loop;

        Read(Axi4MemRec, std_logic_vector(addr), mem_reg);
        AffirmIfEqual(mem_reg, wdata, "Memory data: ");

        Log("Testing SPI register read");
        spi_tx_byte_idx               := 0;
        spi_tx_bytes(spi_tx_byte_idx) := 1; -- 0x01 -> SPI read
        spi_tx_byte_idx               := spi_tx_byte_idx + 1;
        addr                          := x"76543210";
        Log("SPI RD: addr = 0x" & to_hxstring(addr));
        for i in 3 downto 0 loop
            spi_tx_bytes(spi_tx_byte_idx) := to_integer(addr(i * 8 + 7 downto i * 8));
            spi_tx_byte_idx               := spi_tx_byte_idx + 1;
        end loop;
        for i in 0 to 5 loop
            spi_tx_bytes(spi_tx_byte_idx) := 0; -- don't care
            spi_tx_byte_idx               := spi_tx_byte_idx + 1;
        end loop;
        PushBurst(TxBurstFifo, spi_tx_bytes, 8);
        SendBurst(SpiRec, spi_tx_byte_idx);

        -- Get received data
        GetBurst(SpiRec, num_bytes);
        AffirmIfEqual(num_bytes, 11);
        for i in 0 to num_bytes - 1 loop
            PopWord(RxBurstFifo, valid, rx_byte, bytes_to_send);
            AlertIfNot(valid, "invalid receive data");
            Log("RX byte: " & to_string(rx_byte));
            if i = 7 then
                rdata(31 downto 24) := rx_byte;
            elsif i = 8 then
                rdata(23 downto 16) := rx_byte;
            elsif i = 9 then
                rdata(15 downto 8) := rx_byte;
            elsif i = 10 then
                rdata(7 downto 0) := rx_byte;
            end if;
        end loop;
        AffirmIfEqual(rdata, wdata, "SPI read error");

        -- Wait for test to finish
        WaitForBarrier(TestDone, 10 ms);
        AlertIf(now >= 10 ms, "Test finished due to timeout");
        AlertIf(GetAffirmCount < 1, "Test is not Self-Checking");

        TranscriptClose;

        --EndOfTestReports(ExternalErrors => (FAILURE => 0, ERROR => -15, WARNING => 0));
        EndOfTestReports;
        std.env.stop;                   -- (SumAlertCount(GetAlertCount + (FAILURE => 0, ERROR => -15, WARNING => 0)));
        wait;
    end process ControlProc;

end architecture operation1;

Configuration operation1_cfg of tb_spi2axi is
    for TestHarness
        for testctrl_inst : tb_spi2axi_testctrl
            use entity work.tb_spi2axi_testctrl(operation1);
        end for;
    end for;
end operation1_cfg;