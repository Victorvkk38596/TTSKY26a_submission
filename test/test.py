import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

@cocotb.test()
async def test_starfield_vga_audio(dut):
    # 1. Setup the Clock (25.175 MHz)
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
    dut._log.info("Testing HSync Timing...")
    
    while not (int(dut.uo_out.value) & 0x80):
        await RisingEdge(dut.clk)
        
    while (int(dut.uo_out.value) & 0x80):
        await RisingEdge(dut.clk)
    
    start_cycle = cocotb.utils.get_sim_time('ns') / 39.722
    
    while not (int(dut.uo_out.value) & 0x80):
        await RisingEdge(dut.clk)
        
    end_cycle = cocotb.utils.get_sim_time('ns') / 39.722
    
    pulse_width = end_cycle - start_cycle
    dut._log.info(f"HSync Pulse Width: {pulse_width:.2f} cycles")
    assert 90 <= pulse_width <= 100, f"HSync Pulse Width {pulse_width} is incorrect!"

    # 5. Verify Audio PWM Activity
    # Audio waves are slow. We scan up to 100,000 cycles to guarantee we catch a toggle.
    # Checking every 100 cycles avoids slowing down the Python simulation.
    dut._log.info("Testing Audio PWM Activity (Scanning up to 100,000 cycles)...")
    audio_toggled = False 
    
    # We grab the current state of the pin to compare against later.
    last_audio_val = int(dut.uio_out.value) & 0x80 
    
    # --- STEP B: The Observation Loop ---
    for i in range(1000):
        await ClockCycles(dut.clk, 100) # Wait a bit
        current_audio_val = int(dut.uio_out.value) & 0x80
        
        # If the value changed, the hardware is alive!
        if current_audio_val != last_audio_val:
            audio_toggled = True  # FLIP THE FLAG TO TRUE
            break                # Stop searching, we have our proof!
    
    # --- STEP C: The Final Verdict ---
    # If audio_toggled is still False, the assertion triggers a "FAIL"
    assert audio_toggled, "Audio output is dead (not toggling)!"
