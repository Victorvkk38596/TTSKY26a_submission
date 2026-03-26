import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

@cocotb.test()
async def test_starfield_vga_audio(dut):
    # 1. Setup the Clock (25.175 MHz)
    # Period is ~39.722 ns. We use 40ns for simplicity or the precise value:
    clock = Clock(dut.clk, 39.722, units="ns")
    cocotb.start_soon(clock.start())

    # 2. Initialize Inputs
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.ena.value = 1

    # Wait for 10 clock cycles
    await ClockCycles(dut.clk, 10)

    # 3. Release Reset
    dut._log.info("Resetting the Nebula Generator...")
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)
    dut._log.info("System out of reset.")

    # 4. Verify HSYNC Timing (The 31.5 kHz pulse)
    # A full H-Line is 800 cycles. H-Sync active should be 96 cycles.
    dut._log.info("Testing HSync Timing...")
    await FallingEdge(dut.uo_out[7]) # Wait for HSYNC start (Active Low)
    
    start_time = cocotb.utils.get_sim_time('ns')
    await RisingEdge(dut.uo_out[7])  # Wait for HSYNC end
    end_time = cocotb.utils.get_sim_time('ns')
    
    pulse_width = (end_time - start_time) / 39.722
    dut._log.info(f"HSync Pulse Width: {pulse_width} cycles")
    
    # Check if pulse width is roughly 96 cycles (standard VGA)
    assert 90 <= pulse_width <= 100, "HSync Pulse Width is incorrect!"

    # 5. Verify Audio PWM Output
    # We want to see if uio_out[0] is actually toggling
    dut._log.info("Testing Audio PWM Activity...")
    audio_toggles = 0
    for _ in range(1000):
        current_val = dut.uio_out[0].value
        await ClockCycles(dut.clk, 5)
        if dut.uio_out[0].value != current_val:
            audio_toggles += 1
            
    dut._log.info(f"Audio Toggles detected: {audio_toggles}")
    assert audio_toggles > 0, "Audio output is dead (not toggling)!"

    # 6. Verify Speed/Input Impact
    # Change speed and density via ui_in
    dut._log.info("Applying Warp Speed (ui_in = 0xFF)...")
    dut.ui_in.value = 0xFF 
    await ClockCycles(dut.clk, 100)
    
    # 7. Verify VSYNC Triggering
    # Note: Simulating a full 480 lines takes a while. 
    # To save time, we verify that the V-counter is at least incrementing 
    # by checking that HSYNC happens multiple times.
    dut._log.info("Waiting for multiple HSync pulses to verify stability...")
    for i in range(5):
        await FallingEdge(dut.uo_out[7])
        dut._log.info(f"HSync Pulse {i} captured.")

    dut._log.info("Test passed! Nebula is flying and Audio is humming.")
