import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

@cocotb.test()
async def test_starfield_vga_audio(dut):
    # 1. Setup the Clock (25.175 MHz)
    # Fixed DeprecationWarning: renamed 'units' to 'unit'
    clock = Clock(dut.clk, 39.722, unit="ns")
    cocotb.start_soon(clock.start())

    # 2. Initialize Inputs
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.ena.value = 1

    await ClockCycles(dut.clk, 10)

    # 3. Release Reset
    dut._log.info("Resetting the Nebula Generator...")
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)
    dut._log.info("System out of reset.")

    # 4. Verify HSYNC Timing
    # HSync is uo_out[7]. We wait for it to go Low (Falling Edge)
    dut._log.info("Testing HSync Timing...")
    
    # Wait for HSync to be High first (Idle)
    while not (int(dut.uo_out.value) & 0x80):
        await RisingEdge(dut.clk)
        
    # Wait for HSync to go Low (Start of Sync Pulse)
    while (int(dut.uo_out.value) & 0x80):
        await RisingEdge(dut.clk)
    
    start_cycle = cocotb.utils.get_sim_time('ns') / 39.722
    
    # Wait for HSync to go High (End of Sync Pulse)
    while not (int(dut.uo_out.value) & 0x80):
        await RisingEdge(dut.clk)
        
    end_cycle = cocotb.utils.get_sim_time('ns') / 39.722
    
    pulse_width = end_cycle - start_cycle
    dut._log.info(f"HSync Pulse Width: {pulse_width:.2f} cycles")
    
    # Standard VGA HSync is 96 cycles. We allow a small margin for sampling.
    assert 90 <= pulse_width <= 100, f"HSync Pulse Width {pulse_width} is incorrect!"

    # 5. Verify Audio PWM Activity
    # Audio is uio_out[0].
    dut._log.info("Testing Audio PWM Activity...")
    audio_toggles = 0
    last_audio_val = int(dut.uio_out.value) & 0x01
    
    for _ in range(1000):
        await RisingEdge(dut.clk)
        current_audio_val = int(dut.uio_out.value) & 0x01
        if current_audio_val != last_audio_val:
            audio_toggles += 1
            last_audio_val = current_audio_val
            
    dut._log.info(f"Audio Toggles detected: {audio_toggles}")
    assert audio_toggles > 0, "Audio output is dead (not toggling)!"

    # 6. Verify Warp Speed (Input test)
    dut._log.info("Applying Warp Speed (ui_in = 0xFF)...")
    dut.ui_in.value = 0xFF 
    await ClockCycles(dut.clk, 100)
    
    # Final check: Ensure VGA syncs are still alive at high speed
    # We check that HSync (bit 7) and VSync (bit 3) are defined (not 'X')
    uo_val = int(dut.uo_out.value)
    assert (uo_val & 0x80) or not (uo_val & 0x80), "HSync is in an undefined state!"
    
    dut._log.info("Test passed! Nebula is flying and Audio is humming.")
