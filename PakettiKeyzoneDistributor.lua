local dialog = nil
local view_builder = nil
local debug_mode = true -- Set to true to see what's happening

-- Base note calculation modes
local BASE_NOTE_MODES = {
  ORIGINAL = 1,
  LOWEST = 2,
  MIDDLE = 3,
  HIGHEST = 4
}

local function debug_print(...)
  if debug_mode then
    print(...)
  end
end

-- Helper function to ensure we're in the right view and handle dialog state
local function setup_environment()
  -- If dialog is already open, close it and return false
  if dialog and dialog.visible then
    debug_print("Dialog already open, closing...")
    dialog:close()
    dialog = nil
    return false
  end
  
  -- Ensure we're in the keyzone view
  if renoise.app().window.active_middle_frame ~= 
     renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_KEYZONES then
    renoise.app().window.active_middle_frame = 
      renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_KEYZONES
    debug_print("Switched to keyzone view")
  end
  
  return true
end

-- Function to get base note based on mode
local function get_base_note(start_note, end_note, original_base_note, base_note_mode)
  if base_note_mode == BASE_NOTE_MODES.ORIGINAL then
    return original_base_note
  elseif base_note_mode == BASE_NOTE_MODES.LOWEST then
    return start_note
  elseif base_note_mode == BASE_NOTE_MODES.MIDDLE then
    return math.floor(start_note + (end_note - start_note) / 2)
  else -- BASE_NOTE_MODES.HIGHEST
    return end_note
  end
end

-- Function to distribute samples across keyzones
local function distribute_samples(keys_per_sample, base_note_mode)
  local instrument = renoise.song().selected_instrument
  
  if not instrument then
    renoise.app():show_warning("No instrument selected!")
    return
  end
  
  -- Get fresh sample count
  local num_samples = #instrument.samples
  
  if num_samples == 0 then
    renoise.app():show_warning("No samples in instrument!")
    return
  end
  
  debug_print(string.format("Distributing %d samples with %d keys each", num_samples, keys_per_sample))
  
  -- For each sample, update its mapping to the new range
  local mapped_samples = 0
  local reached_limit = false
  
  for sample_idx = 1, num_samples do
    local sample = instrument.samples[sample_idx]
    if sample then
      -- Calculate the new note range (starting from C-0 which is note 0)
      local start_note = (sample_idx - 1) * keys_per_sample
      local end_note = start_note + (keys_per_sample - 1)
      
      -- Check if we would exceed the MIDI range
      if start_note > 119 then
        -- We've reached the limit, stop mapping
        debug_print(string.format("Sample %d would start at note %d (>119), stopping", sample_idx, start_note))
        break
      end
      
      -- Clamp end_note to valid range
      if end_note > 119 then
        end_note = 119
        reached_limit = true
        debug_print(string.format("Sample %d end note clamped from %d to 119", sample_idx, start_note + (keys_per_sample - 1)))
      end
      
      -- Ensure start_note is also within valid range (safety check)
      start_note = math.max(0, math.min(119, start_note))
      end_note = math.max(0, math.min(119, end_note))
      
      -- Ensure start_note <= end_note
      if start_note > end_note then
        debug_print(string.format("Sample %d: start_note (%d) > end_note (%d), skipping", sample_idx, start_note, end_note))
        break
      end
      
      -- Get the original base note before we change anything
      local original_base_note = sample.sample_mapping.base_note
      
      -- Update the mapping range
      sample.sample_mapping.note_range = {
        start_note,  -- Start note (C-0 based)
        end_note     -- End note
      }
      
      -- Set base note according to selected mode
      local new_base_note = get_base_note(start_note, end_note, original_base_note, base_note_mode)
      -- Clamp base note to valid range
      new_base_note = math.max(0, math.min(119, new_base_note))
      sample.sample_mapping.base_note = new_base_note
      
      mapped_samples = mapped_samples + 1
      
      debug_print(string.format(
        "Sample %d mapped to notes %d-%d with base note %d",
        sample_idx, start_note, end_note, new_base_note
      ))
      
      -- If we reached the limit, stop processing more samples
      if reached_limit then
        debug_print(string.format("Reached MIDI range limit at sample %d", sample_idx))
        break
      end
    else
      debug_print(string.format("Sample %d no longer exists, skipping", sample_idx))
    end
  end
  
  -- Show appropriate status message
  if reached_limit then
    renoise.app():show_status(string.format(
      "Mapped %d samples (%d keys each, last sample fit to maximum)",
      mapped_samples, keys_per_sample
    ))
  else
    renoise.app():show_status(string.format(
      "Distributed %d samples across %d keys each",
      mapped_samples, keys_per_sample
    ))
  end
end

-- Show or toggle the Keyzone Distributor dialog
function pakettiKeyzoneDistributorDialog()
  -- Check environment and handle dialog state
  if not setup_environment() then return end
  
  debug_print("Creating new Keyzone Distributor dialog")
  
  -- Build the UI
  view_builder = renoise.ViewBuilder()
  
  local base_note_mode = BASE_NOTE_MODES.MIDDLE -- Default mode
  
  local keys_valuebox = view_builder:valuebox {
    min = 1,
    max = 120, -- Allow full MIDI range per sample
    value = 1, -- Default to single key per sample
    width=50,
    notifier=function(new_value)
      distribute_samples(new_value, base_note_mode)
    end
  }
  
  -- Create quick set buttons
  local function create_quick_set_button(value)
    return view_builder:button {
      text = tostring(value),
      width=35,
      notifier=function()
        keys_valuebox.value = value
        distribute_samples(value, base_note_mode)
      end
    }
  end
  
  local base_note_switch = view_builder:switch {
    width=300,
    items = {"Original", "Lowest Note", "Middle Note", "Highest Note"},
    value = base_note_mode,
    notifier=function(new_mode)
      base_note_mode = new_mode
      -- Redistribute with current keys value but new base note mode
      distribute_samples(keys_valuebox.value, new_mode)
    end
  }
  
  -- Create the dialog
  local keyhandler = create_keyhandler_for_dialog(
    function() return dialog end,
    function(value) dialog = value end
  )
  dialog = renoise.app():show_custom_dialog("Paketti Keyzone Distributor",
    view_builder:column {
      --margin=10,
      --spacing=6,
      view_builder:row {
        view_builder:text {
          width=140,
          text="Distribute Samples by",
          font = "bold",
          style="strong",
        },
        keys_valuebox,
        view_builder:text {
          font="bold",
          style="strong",
          text="keys per sample"
        }
      },
      view_builder:row {
        view_builder:text {
            width=140,
          text="Quick Set",
          font = "bold",
          style="strong",
        },
        create_quick_set_button(1),
        create_quick_set_button(12),
        create_quick_set_button(24)
      },
      view_builder:row {
        view_builder:text {
            width=140,
          text="Base Note",
          font = "bold",
          style="strong",
        },
        base_note_switch
      }
    }, keyhandler
  )
end

renoise.tool():add_keybinding{name="Global:Paketti:Show Keyzone Distributor Dialog...",invoke=function() pakettiKeyzoneDistributorDialog() end}
renoise.tool():add_midi_mapping{name="Paketti:Show Keyzone Distributor Dialog...",invoke=function(message) if message:is_trigger() then pakettiKeyzoneDistributorDialog() end end}
