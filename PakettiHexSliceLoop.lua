-- Helper functions
-- Dialog tracking variable
local dialog = nil

function focus_sample_editor()
    renoise.app().window.active_middle_frame = renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_EDITOR
end

function validate_sample()
    local song=renoise.song()
    local sample = song.selected_sample
    if not sample or not sample.sample_buffer.has_sample_data then
        renoise.app():show_status("No sample selected or sample buffer empty")
        return false
    end
    return song, sample
end

function set_sample_selection_by_hex_offset(hex_value)
    local song=renoise.song()
    local instrument = song.selected_instrument
    if not instrument then
        renoise.app():show_status("No instrument selected")
        return
    end

    -- Convert hex string to number (if string) and ensure it's in 0-FF range
    local value = tonumber(hex_value, 16)
    if not value then
        renoise.app():show_status("Invalid hex value")
        return
    end
    value = math.min(0xFF, math.max(0x00, value))

    -- Check if first sample has slice markers
    local has_slice_markers = instrument.samples[1] and 
                            instrument.samples[1].slice_markers and 
                            #instrument.samples[1].slice_markers > 0

    -- Process all samples in the instrument
    for i = 1, #instrument.samples do
        -- Skip first sample if there are slice markers
        if has_slice_markers and i == 1 then
            -- do nothing for the first sample
        else
            local sample = instrument.samples[i]
            if sample and sample.sample_buffer.has_sample_data then
                local buffer = sample.sample_buffer
                local total_frames = buffer.number_of_frames
                
                -- Calculate percentage (value/255) and apply to total frames
                local target_frame = math.floor((value / 255) * total_frames)
                
                -- Ensure minimum of 1 frame
                target_frame = math.max(1, target_frame)
                
                -- Set selection range and loop points
                buffer.selection_start = 1
                buffer.selection_end = target_frame
                sample.loop_start = 1
                sample.loop_end = target_frame
                sample.loop_mode = renoise.Sample.LOOP_MODE_FORWARD
            end
        end
    end
    
    -- Show info using the selected sample for display
    local selected_sample = song.selected_sample
    if selected_sample and selected_sample.sample_buffer.has_sample_data then
        local buffer = selected_sample.sample_buffer
        local target_frame = math.floor((value / 255) * buffer.number_of_frames)
        local channels_str = buffer.number_of_channels > 1 and "stereo" or "mono"
        local status_msg = string.format(
            "Set %s selection and loop: 1 to %d (%.1f%% at offset S%02X)%s", 
            channels_str,
            target_frame,
            (target_frame / buffer.number_of_frames) * 100,
            value,
            has_slice_markers and " (Skipped sliced sample)" or ""
        )
        renoise.app():show_status(status_msg)
    end
    focus_sample_editor()
end

function pakettiHexOffsetDialog()
if dialog and dialog.visible then
    dialog:close()
    dialog = nil
    return
end

    local song=renoise.song()
    local sample = song.selected_sample
    if not sample or not sample.sample_buffer.has_sample_data then
        renoise.app():show_status("No sample selected or sample buffer empty")
        return
    end

    local vb = renoise.ViewBuilder()
    
    -- Create textfield with immediate update notifier
    local hex_input = vb:textfield {
        id = "hex_input",
        width=50,
        value = "80",
        notifier=function(value)
            if value and value ~= "" then
                set_sample_selection_by_hex_offset(value)
                focus_sample_editor()
            end
        end
    }
    
    -- Create switch for quick hex values
    local hex_switch = vb:switch {
        id = "hex_switch",
        width=200,
        items = {"10", "20", "40", "80"},
        value = 4, -- Default to "80"
        notifier=function(value)
            local hex_value = vb.views.hex_switch.items[value]
            vb.views.hex_input.value = hex_value
            set_sample_selection_by_hex_offset(hex_value)
            focus_sample_editor()
        end
    }
    
    local dialog_content = vb:column{
        margin=5,
        spacing=5,
        
        vb:row{
            vb:text{text="Hex value:" },
            hex_input
        },
        vb:row{
            vb:text{text="Quick select:" },
            hex_switch
        },
        vb:row{
            vb:button{
                text="Set forward loops for all samples",
                width=305,
                notifier=function()
                    set_sample_selection_by_hex_offset(vb.views.hex_input.value)
                    focus_sample_editor()
                end
            }
        }
    }
    
    local function key_handler(dialog, key)
        if key.name == "return" then
            local hex_value = vb.views.hex_input.value
            if hex_value and hex_value ~= "" then
                set_sample_selection_by_hex_offset(hex_value)
            end
            return
        end
        return key
    end
    
    dialog = renoise.app():show_custom_dialog("Set Selection by Hex Offset", dialog_content, my_keyhandler_func) --key_handler)
    focus_sample_editor()
end

function cut_sample_after_selection()
  local song=renoise.song()
  local sample = song.selected_sample
  if not sample or not sample.sample_buffer.has_sample_data then
      renoise.app():show_status("No sample selected or sample buffer empty")
      return
  end

  local buffer = sample.sample_buffer
  local selection_end = buffer.selection_end
  
  if not selection_end then
      renoise.app():show_status("No selection end point set")
      return
  end
  
  buffer:prepare_sample_data_changes()
  
  -- Set all data after selection_end to 0
  for channel = 1, buffer.number_of_channels do
      for frame = selection_end + 1, buffer.number_of_frames do
          buffer:set_sample_data(channel, frame, 0)
      end
  end
  
  buffer:finalize_sample_data_changes()
  renoise.app():show_status(string.format("Cut sample data after frame %d", selection_end))
  renoise.app().window.active_middle_frame = renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_EDITOR
end

function create_instrument_from_selection()
    local song, sample = validate_sample()
    if not song then return end

    local buffer = sample.sample_buffer
    local selection_start = buffer.selection_start
    local selection_end = buffer.selection_end
    
    -- Check if there's a valid selection
    if not selection_start or not selection_end or selection_start >= selection_end then
        renoise.app():show_status("No valid selection range set")
        return
    end
    
    -- Calculate selection length
    local selection_length = selection_end - selection_start + 1
    if selection_length < 1 then
        renoise.app():show_status("Invalid selection range")
        return
    end

    -- Create new instrument
    local new_instrument_index = song.selected_instrument_index + 1
    song:insert_instrument_at(new_instrument_index)
    song.selected_instrument_index = new_instrument_index
    local new_instrument = song:instrument(new_instrument_index)
    
    -- Copy the original instrument name and append "_sel"
    new_instrument.name = sample.name .. "_sel"
    
    -- Ensure we have a sample
    if #new_instrument.samples == 0 then
        new_instrument:insert_sample_at(1)
    end
    local new_sample = new_instrument.samples[1]
    new_sample.name = sample.name .. "_sel"
    
    -- Create new buffer with selection length
    local new_buffer = new_sample.sample_buffer
    new_buffer:create_sample_data(buffer.sample_rate, buffer.bit_depth, buffer.number_of_channels, selection_length)
    new_buffer:prepare_sample_data_changes()
    
    -- Copy the selected portion
    for channel = 1, buffer.number_of_channels do
        for i = 1, selection_length do
            new_buffer:set_sample_data(channel, i, buffer:sample_data(channel, selection_start + i - 1))
        end
    end
    
    new_buffer:finalize_sample_data_changes()
    
    -- Now that we have sample data, set all sample properties
    new_sample.loop_mode = sample.loop_mode
    new_sample.loop_start = 1
    new_sample.loop_end = selection_length
    new_sample.fine_tune = sample.fine_tune
    new_sample.beat_sync_lines = sample.beat_sync_lines
    new_sample.interpolation_mode = sample.interpolation_mode
    new_sample.new_note_action = sample.new_note_action
    new_sample.oneshot = sample.oneshot
    new_sample.autoseek = sample.autoseek
    new_sample.autofade = sample.autofade
    new_sample.sync_to_song = sample.sync_to_song
    
    -- Copy the sample mapping
    new_sample.sample_mapping.base_note = sample.sample_mapping.base_note
    new_sample.sample_mapping.map_velocity_to_volume = sample.sample_mapping.map_velocity_to_volume
    new_sample.sample_mapping.note_range = sample.sample_mapping.note_range
    new_sample.sample_mapping.velocity_range = sample.sample_mapping.velocity_range
    
    renoise.app():show_status(string.format("Created new instrument from selection (frames %d to %d)", selection_start, selection_end))
    
    -- Focus sample editor
    focus_sample_editor()
end

function cut_all_samples_in_instrument()
    -- Get the hex selection value from the original sample
    local song=renoise.song()
    local selected_sample = song.selected_sample
    if not selected_sample or not selected_sample.sample_buffer.has_sample_data then
        renoise.app():show_status("No sample selected or sample buffer empty")
        return
    end

    local selection_end = selected_sample.sample_buffer.selection_end
    if not selection_end then
        renoise.app():show_status("No selection end point set")
        return
    end

    -- Get the hex percentage (0-255 mapped to 0-1)
    local hex_value = math.floor((selection_end / selected_sample.sample_buffer.number_of_frames) * 255)
    
    -- Process all samples in the current instrument
    local instrument = song.selected_instrument
    if not instrument then return end
    
    for i = 1, #instrument.samples do
        local sample = instrument.samples[i]
        if sample and sample.sample_buffer.has_sample_data then
            local buffer = sample.sample_buffer
            -- Calculate frames based on hex value (0-255)
            local target_frame = math.floor((hex_value / 255) * buffer.number_of_frames)
            target_frame = math.max(1, math.min(target_frame, buffer.number_of_frames))
            
            -- Set loop points and enable forward loop
            sample.loop_mode = renoise.Sample.LOOP_MODE_FORWARD
            sample.loop_start = 1
            sample.loop_end = target_frame
        end
    end
    
    renoise.app():show_status(string.format("Set forward loops at hex value %02X", hex_value))
    focus_sample_editor()
end

function prepare_sample_for_slicing()
    print("--- Prepare Sample for Slicing ---")
    
    local song, sample = validate_sample()
    if not song then return end
    
    local instrument = song.selected_instrument
    
    -- Step 1: Clear existing slice markers and create first slice at frame 1, second at last frame
    local total_frames = sample.sample_buffer.number_of_frames
    
    -- Clear slice markers properly
    while #sample.slice_markers > 0 do
        sample:delete_slice_marker(sample.slice_markers[1])
    end
    
    -- Add slice markers properly
    sample:insert_slice_marker(1)  -- First slice at frame 1
    sample:insert_slice_marker(total_frames)  -- Second slice at last frame
    
    print("Created first slice marker at frame 1")
    print("Created second slice marker at frame " .. total_frames .. " (last frame)")
    print("Now drag the second slice LEFT until loop timing is perfect!")
    
    -- Step 2: NOW read the first slice mapping note (after creating slices)
    local first_slice_note = instrument.sample_mappings[1][2].base_note
    
    print("First slice is mapped to note: " .. first_slice_note .. " (" .. note_value_to_string(first_slice_note) .. ")")
    print("This is the note to trigger the first slice")
    
    -- Step 3: Write note to LINE 1 (not current selected line)
    local current_pattern = song.selected_pattern
    local current_track = song.selected_track
    
    -- Make sure we're not on a master or send track
    if current_track.type == renoise.Track.TRACK_TYPE_SEQUENCER then
        local note_column = current_pattern:track(song.selected_track_index):line(1):note_column(1)  -- LINE 1, not current line
        note_column.note_value = first_slice_note  -- Use the first slice note
        note_column.instrument_value = song.selected_instrument_index - 1  -- 0-based
        
        print("Wrote " .. note_value_to_string(first_slice_note) .. " note to pattern at line 1")
    else
        print("Warning: Current track is not a sequencer track - cannot write note")
    end
    
    -- Step 4: Focus sample editor
    focus_sample_editor()
    
    renoise.app():show_status("Sample prepared! Adjust BPM/LPB/Pattern Length, then use Auto-Slice")
    print("--- Sample Preparation Complete ---")
    print("Next steps:")
    print("1. Play the pattern and adjust BPM, LPB, and pattern length")
    print("2. Make sure the sample loops perfectly")
    print("3. Run 'Auto-Slice Using First Slice Length'")
    print("4. Run 'Create Pattern Sequencer Patterns'")
end

function select_beat_range_for_verification()
    print("--- Select Beat Range 1.0.0 to 9.0.0 for Verification ---")
    
    local song, sample = validate_sample()
    if not song then return end
    
    -- Read current song timing
    local bpm = song.transport.bpm
    local sample_rate = sample.sample_buffer.sample_rate
    
    print("Current BPM: " .. bpm)
    print("Sample Rate: " .. sample_rate .. " Hz")
    
    -- Calculate frame position for beat 9.0.0 (8 beats from start)
    local seconds_per_beat = 60 / bpm
    local total_seconds_for_8_beats = 8 * seconds_per_beat
    local frame_position_beat_9 = math.floor(total_seconds_for_8_beats * sample_rate)
    
    print("Seconds per beat: " .. seconds_per_beat)
    print("8 beats duration: " .. total_seconds_for_8_beats .. " seconds")
    print("Frame position of beat 9.0.0: " .. frame_position_beat_9)
    
    -- Set sample selection from frame 1 to beat 9.0.0
    local buffer = sample.sample_buffer
    buffer.selection_start = 1
    buffer.selection_end = frame_position_beat_9
    
    print("Set sample selection: 1 to " .. frame_position_beat_9)
    print("Selection length: " .. frame_position_beat_9 .. " frames")
    print("Selection duration: " .. total_seconds_for_8_beats .. " seconds")
    
    -- Focus sample editor
    focus_sample_editor()
    
    renoise.app():show_status(string.format("Selected 1.0.0 to 9.0.0 (%d frames, %.2fs)", frame_position_beat_9, total_seconds_for_8_beats))
    print("--- Verification Selection Complete ---")
    print("Play this selection to verify it's exactly 8 beats (1.0.0 to 9.0.0)!")
end

function auto_slice_every_8_beats()
    print("--- Auto-Slice every 8 beats ---")
    
    local song, sample = validate_sample()
    if not song then return end
    
    -- Step 1: Select beat range 1.0.0 to 9.0.0 (8 beats)
    local bpm = song.transport.bpm
    local sample_rate = sample.sample_buffer.sample_rate
    
    print("Current BPM: " .. bpm)
    print("Sample Rate: " .. sample_rate .. " Hz")
    
    -- Calculate frame position for beat 9.0.0 (8 beats from start)
    local seconds_per_beat = 60 / bpm
    local total_seconds_for_8_beats = 8 * seconds_per_beat
    local frame_position_beat_9 = math.floor(total_seconds_for_8_beats * sample_rate)
    
    print("8 beats duration: " .. total_seconds_for_8_beats .. " seconds")
    print("Frame position of beat 9.0.0: " .. frame_position_beat_9)
    
    -- Set sample selection from frame 1 to beat 9.0.0
    local buffer = sample.sample_buffer
    buffer.selection_start = 1
    buffer.selection_end = frame_position_beat_9
    
    print("Set sample selection: 1 to " .. frame_position_beat_9)
    
    -- Step 2: Focus sample editor
    focus_sample_editor()
    
    -- Step 3: Auto-slice from selection
    print("Running pakettiSlicesFromSelection() to auto-slice every 8 beats...")
    pakettiSlicesFromSelection()
    
    renoise.app():show_status(string.format("Auto-sliced every 8 beats (%d frames, %.2fs)", frame_position_beat_9, total_seconds_for_8_beats))
    print("--- Auto-Slice every 8 beats Complete ---")
end

function delete_all_pattern_sequences()
    print("--- Delete All Pattern Sequences ---")
    
    local song = renoise.song()
    local sequencer = song.sequencer
    local sequence_count = #sequencer.pattern_sequence
    
    print("Found " .. sequence_count .. " sequences in pattern sequencer")
    
    if sequence_count == 0 then
        renoise.app():show_status("No sequences to delete")
        print("No sequences found")
        return
    end
    
    -- Delete from last to first to avoid index shifting
    for i = sequence_count, 1, -1 do
        print("Deleting sequence at index " .. i)
        sequencer:delete_sequence_at(i)
    end
    
    local remaining_count = #sequencer.pattern_sequence
    print("Sequences remaining after deletion: " .. remaining_count)
    
    renoise.app():show_status("Deleted " .. sequence_count .. " pattern sequences")
    print("--- Delete All Pattern Sequences Complete ---")
end

function whole_hog_complete_workflow()
    print("=== WHOLE HOG: Complete Sample to Pattern Workflow ===")
    
    local song, sample = validate_sample()
    if not song then return end
    
    print("Step 1/3: Preparing sample for slicing...")
    
    -- STEP 1: Prepare sample (from prepare_sample_for_slicing)
    local instrument = song.selected_instrument
    local total_frames = sample.sample_buffer.number_of_frames
    
    -- Clear existing slice markers and create first slice at frame 1, second at last frame
    while #sample.slice_markers > 0 do
        sample:delete_slice_marker(sample.slice_markers[1])
    end
    
    sample:insert_slice_marker(1)  -- First slice at frame 1
    sample:insert_slice_marker(total_frames)  -- Second slice at last frame
    
    print("Created preparation slices at frame 1 and " .. total_frames)
    
    -- Read the first slice mapping note and write to pattern
    local first_slice_note = instrument.sample_mappings[1][2].base_note
    local current_pattern = song.selected_pattern
    local current_track = song.selected_track
    
    if current_track.type == renoise.Track.TRACK_TYPE_SEQUENCER then
        local note_column = current_pattern:track(song.selected_track_index):line(1):note_column(1)
        note_column.note_value = first_slice_note
        note_column.instrument_value = song.selected_instrument_index - 1
        print("Wrote " .. note_value_to_string(first_slice_note) .. " note to pattern line 1")
    end
    
    print("Step 2/3: Auto-slicing every 8 beats...")
    
    -- STEP 2: Auto-slice every 8 beats (from auto_slice_every_8_beats)
    local bpm = song.transport.bpm
    local sample_rate = sample.sample_buffer.sample_rate
    local seconds_per_beat = 60 / bpm
    local total_seconds_for_8_beats = 8 * seconds_per_beat
    local frame_position_beat_9 = math.floor(total_seconds_for_8_beats * sample_rate)
    
    print("BPM: " .. bpm .. ", 8 beats = " .. total_seconds_for_8_beats .. "s, Frame: " .. frame_position_beat_9)
    
    -- Set sample selection and auto-slice
    local buffer = sample.sample_buffer
    buffer.selection_start = 1
    buffer.selection_end = frame_position_beat_9
    
    focus_sample_editor()
    
    print("Running pakettiSlicesFromSelection()...")
    pakettiSlicesFromSelection()
    
    print("Step 3/3: Creating pattern sequencer patterns...")
    
    -- STEP 3: Create pattern sequencer patterns
    print("Running createPatternSequencerPatternsBasedOnSliceCount()...")
    createPatternSequencerPatternsBasedOnSliceCount()
    
    renoise.app():show_status("WHOLE HOG Complete! Sample prepared, sliced, and patterns created")
    print("=== WHOLE HOG COMPLETE! ===")
    print("Sample is now ready to use with pattern sequencer!")
end

function detect_first_slice_and_auto_slice()
    print("--- Detect First Slice and Auto-Slice ---")
    
    local song, sample = validate_sample()
    if not song then return end
    
    local slice_markers = sample.slice_markers
    local slice_count = #slice_markers
    
    -- Check if we have at least 2 slices to determine first slice length
    if slice_count < 2 then
        renoise.app():show_status("Need at least 2 slices to detect first slice length")
        print("Error: Need at least 2 slices to detect first slice length")
        return
    end
    
    -- Get first slice boundaries
    local slice1_start = slice_markers[1]
    local slice1_end = slice_markers[2] - 1  -- End of slice 1 is start of slice 2 minus 1
    local slice1_length = slice1_end - slice1_start + 1
    
    print("Detected slice 1: Start=" .. slice1_start .. ", End=" .. slice1_end .. ", Length=" .. slice1_length .. " frames")
    
    -- Set sample selection to first slice range
    local buffer = sample.sample_buffer
    buffer.selection_start = slice1_start
    buffer.selection_end = slice1_end
    
    print("Set sample selection: " .. slice1_start .. " to " .. slice1_end)
    
    -- Focus sample editor so user can see the selection
    focus_sample_editor()
    
    -- Call pakettiSlicesFromSelection to auto-slice the rest
    print("Running pakettiSlicesFromSelection() to auto-slice remaining sample...")
    pakettiSlicesFromSelection()
    
    renoise.app():show_status(string.format("Auto-sliced sample using first slice length (%d frames)", slice1_length))
    print("--- Auto-Slice Complete ---")
end
