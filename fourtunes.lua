-- fourtunes v 1.0
--
-- A 4-track polyphonic step 
-- sequencer with a polysynth 
-- thrown in for good measure.
--
-- MIDI input required!
--
-- K1 : shift
-- E1 : select track
-- K1 + E1 : select page
--
-- E2 + E3 : change page params
-- K2 : page action 1
-- K3 : page action 2

-------------------------------------
-- Hey! There's some parts of this
-- code that aren't great. Learning
-- as I went and definitely wrote
-- myself into some corners.
--
-- If you see something that looks weird 
-- it probably is, and I probably agree 
-- with you (or I'm blissfully unaware).
-------------------------------------

local er = require 'er'
local mu = require "musicutil"
local fileselect = require 'fileselect'
local textentry = require 'textentry'

local scales = {}
local scale_notes = {}
local activenotes = {}
local rates = { {"4",4},     {"3",3} ,      {"2",2},     {"1",1},
                {"1/2",1/2}, {"1/3",1/3},   {"1/4",1/4}, {"1/6",1/6},
                {"1/8",1/8}, {"1/12",1/12}, {"1/16",1/16}
              }

local sequences = {}
local patterns = {{}, {}, {}, {}, {}, {}, {}, {}} 
local currpattern = 1
local nextpattern = 1
local transReset = false
local patternwait = 1
local tracks = {}
local currtrack = 1


local noteCount = 0
local newNotes = {}
local recording = false
local playing = false
local editing = false
local recFlash = false
local recMode = 1
local recModes = {"Append", "Overdub", "Replace"}
local newRecNote = false

local trigIndicator = {false, false, false, false}

local m_out = midi.connect()
local m_in = midi.connect()
local offon = {"Off", "On"}

local shift = false

local paramSel = 1
local pageParamSel = {1, 1, 1, 1, 1, 1, 1, 1, 1}
local pageMode = 2 -- 1 = edit, 2 = rec/play, 3 = trigs, 4 = euclidean trigs, 5 = transpositions, 6 = outputs, 7 = synth, 8 = load/save, 9 = patterns

local pages = {{title = "Edit Pitches", paramGroups = 2},
               {title = "Record/Play", paramGroups = 2},
               {title = "Triggers", paramGroups = 3},
               {title = "Euclidean Triggers", paramGroups = 3},
               {title = "Transpositions", paramGroups = 2},
               {title = "Track Outputs", paramGroups = 4},
               {title = "Synth Edit", paramGroups = 4},
               {title = "Load/Save", paramGroups = 2},
               {title = "Patterns", paramGroups = 1}
              }


local storage = _path.data.."fourtunes/"
local bufferFile = "buffer.txt"
local currFile = "buffer"
local filesel = false

local saveFlash = false
local loadFlash = false
local bufferFlash = false
local editFlash = false
local patternFlash = false

local midiOptions = {}
local project = {}

engine.name = "MollyThePoly"
local MollyThePoly = require "molly_the_poly/lib/molly_the_poly_engine"

function init()
  set_enc_accel(false)

  check_dir(storage.."params")

  clear_buffer()

  fill_scales()
  add_scale_params()
  add_midi_params()
  add_track_params()
  MollyThePoly.add_params()
 
  m_in.event = midi_input_rec_handler

  load_table()
  
  drawClock = metro.init(int_clk, 0.002, -1)
  drawClock:start()
 
  params:bang()
 
end

function check_file(filename)
  if os.rename(filename, filename) == nil then
    return false
  end
  return true
  
end

function check_dir(dirname)
  if os.rename(dirname, dirname) == nil then
    os.execute("mkdir "..dirname)
  end
end

function load_table(filename)
  local file = (filename ~= nil and filename) or storage..bufferFile
  local fin = io.open(file)
  filesel = false
  if fin ~= nil then  
    io.close(fin)
    patterns = tab.load(file)
    tracks = patterns[1]
    print("File Loaded: "..file)
    currFile = file:sub(#storage+1, #file-4)
    if check_file(storage.."params/"..currFile.."_params.pset") then
      params:read(storage.."params/"..currFile.."_params.pset") 
    end
    clock.run(flash_message, "load")
  else
    print("File load cancelled.")
  end

end

function save_table(filename)
  filename = filename == nil and "buffer" or filename
  if filename ~= "" then
    params:write(storage.."params/"..filename.."_params.pset", "")
    filename = filename..".txt"
    write_midi_options()
    print("Table saved")
    tab.save(patterns, storage..filename)
    if filename:sub(1, #filename-4) ~= "buffer" then
      currFile = filename:sub(1, #filename-4)
      print("Project saved: "..filename)
      clock.run(flash_message, "save")
    end
  else
    print("Save cancelled.")
  end
 
end

function write_midi_options()
  midiOptions = {}
  table.insert(midiOptions, params:get("midi_in_device"))
  table.insert(midiOptions, params:get("midi_out_device"))
  for i = 1, 4 do
    table.insert(midiOptions, params:get("mchan_t"..i))  
  end
 
end

function read_midi_options(t)
  params:set("midi_in_device", t[1])
  params:set("midi_out_device", t[2])
  for i = 3, 6 do
    params:set("mchan_t"..(i-2), t[i])
  end
 
end

function read_seq_params(t)
  for i = 1, 4 do
    params:set("t"..i.."_shift", t[i].pitchShift)
    params:set("t"..i.."_length", t[i].length)
  end
 
end

function clear_buffer()
  for i = 1, 8 do
    for j = 1, 4 do
      patterns[i][j] = new_track()
    end
  end
  tracks = patterns[1]  
  currFile = "buffer"
  currpattern = 1
  nextpattern = 1
  
end

function new_track()
  return {
    seq = {},
    seqIdx = 0,
    length = 0,
    rateIdx = 7,
    rate = rates[7][2],
    rateStr = rates[7][1],
    transpose = {0, 0, 0, 0, 0, 0, 0, 0},
    transIdx = 1,
    transSel = 1,
    transLength = 1,
    transWhen = 0,
    transMute = false,
    trigs = new_trigs(),
    trigIdx = 1,
    trigSel = 1,
    trigsLen = 4,
    erTrigs = {false},
    erTrigIdx = 1,    
    erTrigRotation = 0,
    erProb = 100,
    erMute = false,
    k = 1,
    n = 0,
    gate = 0.25,
    newRecording = true,
    mute = false,
    pitchShift = 0,
    mChan = 1
  }

end

function new_trigs()
  local trigs = {}
  for i = 1, 16 do
    table.insert(trigs, new_trig())
  end
  trigs[1].state = true
  return trigs

end

function new_trig()
    return {
      state = false,
      prob = 100,
      slop = 0
    }
   
end  


function int_clk()
  redraw()

end

function add_midi_params()
  params:add_separator()
  params:add{type = "option",
             id = "midi_output",
             name = "MIDI output",
             options = offon,
             default = 2
            }

  params:add_separator()
  params:add{type = "number",
             id = "midi_in_device",
             name = "MIDI in device",
             min = 1,
             max = 4,
             default = 1,
             action = function(value)
                          midi:cleanup()
                          m_in = midi.connect(value)
                          m_in.event = midi_input_rec_handler
                      end
             }

  params:add{type = "number",
             id = "midi_out_device",
             name = "MIDI out device",
             min = 1,
             max = 4,
             default = 1,
             action = function(value)
                         allnotesoff()
                         m_out = midi.connect(value)
                      end
             }

  params:add_separator()
  for i = 1, 4 do
    params:add{type = "number",
               id = "mchan_t"..i,
               name = "MIDI out channel T"..i,
               min = 1,
               max = 16,
               default = 1,
               action = function(value)
                         allchannotesoff(tracks[i].mChan)
                         tracks[i].mChan = value
                        end
               }
  end
 
end


function allchannotesoff(mChan)
  for i = 1, #activenotes do
      m_out:note_off(activenotes[i], 0, mChan)      
  end

end

function allnotesoff()
    for i = 1, #tracks do
      for j = 1, #activenotes do
          m_out:note_off(activenotes[j], 0, tracks[i].mChan)      
      end
    end
    activenotes = {}

end
 

function fill_scales()
  for i=1,#mu.SCALES do
    scales[i] = mu.SCALES[i].name
  end

end

function add_track_params()
  params:add_separator()
  for i = 1, 4 do
    params:add_option("track_"..i.."_output", "Track "..i.." Output", {"Both", "MIDI", "Synth"}, 1)
  end
 
  params:add_separator()
  params:add_option("editEnable", "Edit Pitches", {"Enabled", "Disabled"}, 1)
  params:add_separator()
 
end

function add_scale_params()
  params:add_separator()
 
  params:add_option("scale", "scale", scales, 47)
  params:set_action("scale", build_scale)

  params:add_option("root", "root", mu.NOTE_NAMES)
  params:set_action("root", build_scale)
 
end

function play()
  for i = 1, 4 do
    sequences[i] = clock.run(play_seq, i)  
  end
 
end

function stop()
  for i = 1, #sequences do
    clock.cancel(sequences[i])
  end
  for i = 1, 4 do
    tracks[i].seqIdx = 0  
  end
  save_table()
 
end

function midi_input_rec_handler(data)
  d = midi.to_msg(data)
  
  if recording then
    if d.type =="note_on" then
      newRecNote = true
      noteCount = noteCount + 1
      table.insert(newNotes, {d.note, 100})
      engine.noteOn(d.note, mu.note_num_to_freq(d.note), 127)
    end
    if d.type == "note_off" then
      noteCount = noteCount - 1
      engine.noteOff(d.note)
    end
    if d.type == "note_off" and noteCount == 0 then
      if recMode == 1 then
        --append mode (default)
        table.insert(tracks[currtrack].seq, newStep(newNotes))
      elseif recMode == 2 then  
        --overdub mode
        for i = 1, #newNotes do
          table.insert(tracks[currtrack].seq[tracks[currtrack].seqIdx].notes, newNotes[i])
        end
      elseif recMode == 3 then
        --replace mode
        tracks[currtrack].seq[tracks[currtrack].seqIdx].notes = newNotes
      end
      newNotes = {}
      tracks[currtrack].length = #tracks[currtrack].seq
      tracks[currtrack].newRecording = false
      engine.noteOff(d.note)
    end
    --echo midi input
    m_out:send(data)
  
  elseif editing and (#tracks[currtrack].seq > 0) then
    if d.type == "note_on" then
      noteCount = noteCount + 1
      table.insert(newNotes, {d.note, 100})
      engine.noteOn(d.note, mu.note_num_to_freq(d.note), 127)
    end
    if d.type == "note_off" then
      noteCount = noteCount - 1
      engine.noteOff(d.note)
    end
    if d.type == "note_off" and noteCount == 0 then
      tracks[currtrack].seq[tracks[currtrack].seqIdx].notes = newNotes
      engine.noteOff(d.note)
      clock.run(flash_message, "edit")
      newNotes = {}
    end
    --echo midi input
    m_out:send(data)
  
  else    
    if d.type == "note_on" then
      engine.noteOn(d.note, mu.note_num_to_freq(d.note), 127)
    elseif d.type == "note_off" then
      engine.noteOff(d.note)
    end
  end
   
end

function newStep(newNotes)
  return {notes = newNotes,
          prob = 100, -- no longer needed
          cond = {1,1} -- no longer needed
         }
         
end

function play_seq(track)
  local trans_idx = 1  
  local trigIdx = 1
  local erTrigIdx = 1  
  local transCount = 1
 
  while true do
    local seq_idx = 1
    if #tracks[track].seq > 0 then
      while seq_idx <= (tracks[track].length) do  
        local notequeue = {}
        local probability = false
        
        if transReset then
          trans_idx = 1
          transReset = false
        end
        
        local transposeVal = (tracks[track].transMute and 0 or tracks[track].transpose[trans_idx])
       
        for i = 1, #tracks[track].seq[seq_idx].notes do
          table.insert(notequeue, mu.snap_note_to_array((tracks[track].seq[seq_idx].notes[i][1] + transposeVal) + tracks[track].pitchShift, scale_notes))
        end
       
        clock.sync(tracks[track].rate)
        tracks[track].transIdx = trans_idx    
        if (tracks[track].erTrigs[erTrigIdx] or tracks[track].trigs[trigIdx].state) then
          if (tracks[track].erTrigs[erTrigIdx] and not tracks[track].erMute) and tracks[track].erProb >= math.random(100) then
              probability = true
          end
          if tracks[track].trigs[trigIdx].state and tracks[track].trigs[trigIdx].prob >= math.random(100) then
              probability = true
          end
 
          if probability then
              for i = 1, #notequeue do
                if not tracks[track].mute then
                   if tracks[track].trigs[trigIdx].slop > 0 and (i > 1 or #notequeue == 1) then
                     clock.sleep(math.random(tracks[track].trigs[trigIdx].slop)/1000)
                   end
                  play_midi(notequeue[i], tracks[track].gate, tracks[track].mChan, params:get("track_"..track.."_output"))
                end
              end
              --set trigIndicator[currtrack] == true for a short amount of time.
              if not tracks[track].mute then
                clock.run(set_trig_indicator, track)
              end
              tracks[track].seqIdx = seq_idx
              seq_idx = seq_idx + 1          
              if (tracks[track].transWhen > 0 and transCount % tracks[track].transWhen == 0) then
                trans_idx = (trans_idx % tracks[track].transLength) + 1
              end
              transCount = transCount + 1
          end
        end
        tracks[track].erTrigIdx = erTrigIdx
        erTrigIdx = (erTrigIdx % #tracks[track].erTrigs) + 1
        tracks[track].trigIdx = trigIdx
        trigIdx = (trigIdx % tracks[track].trigsLen) + 1
      end
      --transpose at the end of each sequence
      if tracks[track].transWhen == 0 then
        trans_idx = (trans_idx % tracks[track].transLength) + 1
      end
    else
      clock.sync(tracks[track].rate)
    end
  end

end  

function play_seq_edit(track)
  local notequeue = {}
  local seq_idx = tracks[track].seqIdx
 
  --queue notes up
  for i = 1, #tracks[track].seq[seq_idx].notes do
    table.insert(notequeue, mu.snap_note_to_array(tracks[track].seq[seq_idx].notes[i][1], scale_notes))
  end

  --spit notes out
  for i = 1, #notequeue do
    play_midi(notequeue[i], tracks[track].gate, tracks[track].mChan, params:get("track_"..track.."_output"))
  end

end

function set_trig_indicator(track)
  trigIndicator[track] = true
  clock.sleep(0.1)
  trigIndicator[track] = false
 
end

function play_midi(note, duration, chan, trackOutput)
  local q_note = mu.snap_note_to_array(note, scale_notes)
  if trackOutput == 1 or trackOutput == 2 then
    m_out:note_on(q_note, 127, chan)
  end
  if trackOutput == 1 or trackOutput == 3 then
    engine.noteOn(q_note, mu.note_num_to_freq(q_note), 127)
  end
  table.insert(activenotes, q_note)
  clock.run(midi_note_off, q_note, duration, chan, trackOutput)
 
end

function midi_note_off(note, duration, chan, trackOutput)
  clock.sleep(duration)
  if trackOutput == 1 or trackOutput == 2 then
    m_out:note_off(note, 127, chan)
  end
  if trackOutput == 1 or trackOutput == 3 then
    engine.noteOff(note)
  end
  table.remove(activenotes)
  
end

function eng_play_note(note)
  q_note = mu.snap_note_to_array(note, scale_notes)
  engine.hz(mu.note_num_to_freq(q_note))
 
end

function build_scale()
  scale_notes = mu.generate_scale(params:get("root") - 1, params:get("scale"), 10)
 
end

function key(n, z)
  if n == 1 then
    if z == 1 then
      shift = true
    else
      shift = false
    end
  end
 
  if pageMode == 1 then
    if n == 2 and z == 1 then
      if tracks[currtrack].seqIdx > 0 then
        play_seq_edit(currtrack)
      end
    elseif n == 3 and z == 1 then
      editing = false
      pageMode = 2
    end
  end
 
  if pageMode == 2 then
    if n == 2 and z == 1 then
      if shift then
        tracks[currtrack] = new_track()
      elseif not recording then
        tracks[currtrack].mute = not tracks[currtrack].mute
      elseif recMode == 1 then
        table.remove(tracks[currtrack].seq)
        tracks[currtrack].length = #tracks[currtrack].seq
      end
    elseif n == 3 and z == 1 then
      if shift then
        recording = not recording
        if recording then
          newRecNote = false
          flashclock = clock.run(rec_message)
          if #tracks[currtrack].seq == 0 then
            recMode = 1
          end
        else
          clock.cancel(flashclock)
          recFlash = false
          save_table()
          tracks[currtrack].newRecording = false
        end
      else
        if recording then
          recording = not recording
          clock.cancel(flashclock)
          recFlash = false
          save_table()
          tracks[currtrack].newRecording = false
        else
          if playing then
            playing = false
            stop()
          else
            playing = true
            play()
          end
        end
      end
    end
  end
 
  if pageMode >= 3 and pageMode <= 7 then 
    if n == 2 and z == 1 then
      if shift then
        pageParamSel[pageMode] = pageParamSel[pageMode] - 1
        if paramSel <= 0 then
          pageParamSel[pageMode] = pages[pageMode].paramGroups
        end
      else
        pageParamSel[pageMode] = (pageParamSel[pageMode] % pages[pageMode].paramGroups) + 1
      end
      paramSel = pageParamSel[pageMode]
    end
  end
 
  if pageMode == 3 then
    if n == 3 and z == 1 then
      if shift then
        tracks[currtrack].trigs[tracks[currtrack].trigSel].state = false
      else  
        tracks[currtrack].trigs[tracks[currtrack].trigSel].state = true
      end
    end
  end
 
  if pageMode == 4 then
    if n == 3 and z == 1 then
      tracks[currtrack].erMute = not tracks[currtrack].erMute
    end
  end

  if pageMode == 5 then
    if n == 3 and z == 1 then
      tracks[currtrack].transMute = not tracks[currtrack].transMute
    end
  end
 
  if pageMode == 8 then
    if n == 2 and z == 1 then
      if shift then
        clear_buffer()
        clock.run(flash_message, "buffer")
        save_table()
      else
        filesel = true
        fileselect.enter(storage, function(txt) load_table(txt) end)
      end
    end
    if n == 3 and z == 1 then
      textentry.enter(function(txt) save_table(txt) end, (currFile == "buffer" and "" or currFile), "Save As:")
    end
  end
 
 if pageMode == 9 then
  if n == 2 and z == 1 then
    if shift and currpattern <= 7 then
      patterns[currpattern + 1] = t_deepcopy(patterns[currpattern])
      currpattern = currpattern + 1
      nextpattern = currpattern
      tracks = patterns[currpattern]
    else
      clock.run(wait_for_q)
    end
    clock.run(flash_message, 'pattern')
  end
  if n == 3 and  z == 1 then
    if shift then 
      pageMode = 2
    elseif playing then
      stop()
      playing = false
    else
      play()
      playing = true
    end
  end
 end
 
end

function wait_for_q()
  clock.sync(1/16)
  currpattern = nextpattern
  tracks = patterns[currpattern]
  transReset = true
  
end

function set_enc_accel(data)
  for i = 1, 3 do
    norns.enc.accel(i, data)
  end
 
end

function enc(n, d)
  if n == 1 then
    if shift then
      pageMode = util.clamp(pageMode + d, (params:get("editEnable") == 1 and 1 or 2), #pages)
      paramSel = pageParamSel[pageMode]
      editing = false
      if recording then
          recording = false
          clock.cancel(flashclock)
          recFlash = false
          tracks[currtrack].newRecording = false
      end
      if pageMode == 1 then
        stop()
        playing = false
        recording = false
        editing = true
        for i = 1, 4 do
          if #tracks[i].seq > 0 then
            tracks[i].seqIdx = 1
          end
        end
      elseif pageMode == 9 then
        nextpattern = currpattern
      end
    else
      currtrack = util.clamp(currtrack + d, 1, 4)
    end
  elseif pageMode == 1 then
    enc_edit_handler(n,d)
  elseif pageMode == 2 then
    enc_play_rec_handler(n,d)
  elseif pageMode == 3 then
    enc_trigs_handler(n,d)
  elseif pageMode == 4 then
    enc_euc_trigs_handler(n,d)
  elseif pageMode == 5 then
    enc_transpositions_handler(n,d)
  elseif pageMode == 6 then
    enc_output_handler(n, d)
  elseif pageMode == 7 then
    enc_synth_edit_handler(n, d)
  elseif pageMode == 9 then
    enc_patterns_handler(n, d)
  end
 
end

function enc_play_rec_handler(n, d)
  if n == 2 then
    if paramSel == 1 then
        tracks[currtrack].pitchShift = util.clamp(tracks[currtrack].pitchShift + d, -36, 36)
    end
  elseif n == 3 then
    if paramSel == 1 then
      if recording and playing and #tracks[currtrack].seq > 0 then
        recMode = util.clamp(recMode + d, 1, 3)
      else
        tracks[currtrack].length = util.clamp(tracks[currtrack].length + d, 1, #tracks[currtrack].seq)
      end
    end
  end
  
end

function enc_edit_handler(n, d)
  prevIdx = tracks[currtrack].seqIdx
 
  if n == 2 and tracks[currtrack].seqIdx ~= 0 then
    if #tracks[currtrack].seq[tracks[currtrack].seqIdx].notes == 1 then
      tracks[currtrack].seq[tracks[currtrack].seqIdx].notes[1][1] = util.clamp(tracks[currtrack].seq[tracks[currtrack].seqIdx].notes[1][1] + (shift and d*12 or d), 0, 127)
    elseif #tracks[currtrack].seq[tracks[currtrack].seqIdx].notes > 1 then
      local val = 0
      local temp = tracks[currtrack].seq[tracks[currtrack].seqIdx].notes
     
      if not shift then
        for i=1, #temp do
          temp[i][1] = temp[i][1] + d
        end
      else
        if d > 0 then
          val = temp[1][1]
          if (val + 12) < 127 then
            table.remove(temp, 1)
            table.insert(temp, {val + 12, 100})
            tracks[currtrack].seq[tracks[currtrack].seqIdx].notes = temp
            temp = {}
          end
        else
          val = temp[#temp][1]
          if (val - 12) > 0 then
            table.remove(temp)
            table.insert(temp, 1, {val - 12, 100})
            tracks[currtrack].seq[tracks[currtrack].seqIdx].notes = temp
            temp = {}
          end
        end
      end
    end
    play_seq_edit(currtrack)
  end
 
  if n == 3 then
    tracks[currtrack].seqIdx = util.clamp(tracks[currtrack].seqIdx + d, 1, #tracks[currtrack].seq)
    if tracks[currtrack].seqIdx ~= prevIdx then
      play_seq_edit(currtrack)
    end
  end
 
end

function enc_trigs_handler(n, d)
    if n == 2 then
      if paramSel == 1 then
        --select trigger
        tracks[currtrack].trigSel = util.clamp(tracks[currtrack].trigSel + d, 1, tracks[currtrack].trigsLen)
      elseif paramSel == 2 then
        --set trigger slop
        tracks[currtrack].trigs[tracks[currtrack].trigSel].slop = util.clamp(tracks[currtrack].trigs[tracks[currtrack].trigSel].slop + d, 0, 100)
      elseif paramSel == 3 then
        --set track gate time
        local val = (shift and 10 or 100)
        tracks[currtrack].gate = util.clamp(tracks[currtrack].gate + (d/val), 0.01, 10)
      end
    elseif n == 3 then
      if paramSel == 1 then
        --set length of trig sequence
        tracks[currtrack].trigsLen = util.clamp(tracks[currtrack].trigsLen + d, 1, 16)
      elseif paramSel == 2 then
        --set selected trigger probability
        tracks[currtrack].trigs[tracks[currtrack].trigSel].prob = util.clamp(tracks[currtrack].trigs[tracks[currtrack].trigSel].prob + d, 1, 100)
      elseif paramSel == 3 then
        tracks[currtrack].rateIdx = util.clamp(tracks[currtrack].rateIdx + d, 1, #rates)
        tracks[currtrack].rateStr = rates[tracks[currtrack].rateIdx][1]
        tracks[currtrack].rate = rates[tracks[currtrack].rateIdx][2]
      end
    end
 
end
 

function enc_euc_trigs_handler(n, d)
  if n == 2 then
    if paramSel == 1 then
      --set number of trigs
      tracks[currtrack].n = util.clamp(tracks[currtrack].n + d, 0, tracks[currtrack].k)
      if tracks[currtrack].n > 0 then
        tracks[currtrack].erTrigs = er.gen(tracks[currtrack].n, tracks[currtrack].k)
        rotate_table(tracks[currtrack].erTrigs, 1, tracks[currtrack].erTrigRotation)
      else
        tracks[currtrack].erTrigs = {false}
      end
    elseif paramSel == 2 then
      --rotate trigs
      tracks[currtrack].erTrigRotation = (tracks[currtrack].erTrigRotation + d) % tracks[currtrack].k
      rotate_table(tracks[currtrack].erTrigs, d)
    elseif paramSel == 3 then
      --set track gate time
      tracks[currtrack].gate = util.clamp(tracks[currtrack].gate + (d/100), 0.01, 10)
    end
  elseif n == 3 then
    if paramSel == 1 then
      tracks[currtrack].k = util.clamp(tracks[currtrack].k + d, 1, 16)
      if tracks[currtrack].n > 0 then
        tracks[currtrack].erTrigs = er.gen(tracks[currtrack].n, tracks[currtrack].k)
        rotate_table(tracks[currtrack].erTrigs, 1, tracks[currtrack].erTrigRotation)
      end
    elseif paramSel == 2 then
      tracks[currtrack].erProb = util.clamp(tracks[currtrack].erProb + d, 1, 100)
    elseif paramSel == 3 then
      tracks[currtrack].rateIdx = util.clamp(tracks[currtrack].rateIdx + d, 1, #rates)
      tracks[currtrack].rateStr = rates[tracks[currtrack].rateIdx][1]
      tracks[currtrack].rate = rates[tracks[currtrack].rateIdx][2]
    end
  end

end

function enc_transpositions_handler(n, d)
    if n == 2 then
      if paramSel == 1 then
        --select transpose list entry
        tracks[currtrack].transSel = util.clamp(tracks[currtrack].transSel + d, 1, tracks[currtrack].transLength)
      elseif paramSel == 2 then
        --set transposition list length
        tracks[currtrack].transLength = util.clamp(tracks[currtrack].transLength + d, 1, #tracks[currtrack].transpose)
      end
    elseif n == 3 then
      if paramSel == 1 then
        --set transpose shift value for selected step
        tracks[currtrack].transpose[tracks[currtrack].transSel] = util.clamp(tracks[currtrack].transpose[tracks[currtrack].transSel] + d, -24, 24)
      elseif paramSel == 2 then
        --set the "when" value 
        tracks[currtrack].transWhen = util.clamp(tracks[currtrack].transWhen + d, 0, 64)        
      end
    end
 
end

function enc_synth_edit_handler(n, d)
    if n == 2 then
      if paramSel == 1 then
        params:delta("osc_wave_shape", d)
      elseif paramSel == 2 then
        params:delta("pulse_width_mod", d)
      elseif paramSel == 3 then
        params:delta("lp_filter_cutoff", d)
      elseif paramSel == 4 then
        params:delta("env_2_attack", d)
      end
    elseif n == 3 then
      if paramSel == 1 then
        params:delta("sub_osc_level", d)
      elseif paramSel == 2 then
        params:delta("lfo_freq", d)
      elseif paramSel == 3 then
        params:delta("lp_filter_resonance", d)
      elseif paramSel == 4 then
        params:delta("env_2_release", d)
      end
    end
 
end

function enc_output_handler(n, d)
    if n == 2 then
      if paramSel == 1 then
        params:delta("track_1_output", d)
      elseif paramSel == 2 then
        params:delta("track_2_output", d)
      elseif paramSel == 3 then
        params:delta("track_3_output", d)
      elseif paramSel == 4 then
        params:delta("track_4_output", d)
      end
    elseif n == 3 then
      if paramSel == 1 then
        params:delta("mchan_t1", d)
      elseif paramSel == 2 then
        params:delta("mchan_t2", d)
      elseif paramSel == 3 then
        params:delta("mchan_t3", d)
      elseif paramSel == 4 then
        params:delta("mchan_t4", d)
      end
    end
 
end

function enc_patterns_handler(n, d)
    if n == 2 then
      if paramSel == 1 then
        nextpattern = util.clamp(nextpattern + d, 1, 8)
      end
    end
end


function rotate_table(t, dir, rot)
  local rot = rot or 1
 
  for i = 1, rot do
    if dir >= 0 then
      table.insert(t, 1, table.remove(t, #t))
    else
      table.insert(t, #t, table.remove(t, 1))  
    end
  end
 
end

function redraw()
  local str = ""
 
  screen.clear()
  draw_header()
 
  if pageMode == 1 then
    draw_edit()
  elseif pageMode == 2 then
    draw_recplay()
  elseif pageMode == 3 then
    draw_trigs()
  elseif pageMode == 4 then
    draw_euclidian_trigs()
  elseif pageMode == 5 then
    draw_transpositions()
  elseif pageMode == 6 then
    draw_outputs()    
  elseif pageMode == 7 then
    draw_synth_edit()
  elseif pageMode == 8 then
    draw_load_save()
  elseif pageMode == 9 then
    draw_patterns()
  end
 
  draw_footer()
  draw_footer_text()
 
  if not filesel then
    screen.update()
  end
 
end

function draw_header()
  screen.level(3)
  screen.move(1, 9)
  screen.line(128, 10)
  screen.move(18, 9)
  screen.line(18, 0)
  screen.move(110, 9)
  screen.line(110, 0)
  screen.stroke()

  screen.level(trigIndicator[1] and 15 or 1)
  screen.circle(118, 2, 1)
  screen.fill()
  screen.level(trigIndicator[2] and 15 or 1)
  screen.circle(123, 2, 1)
  screen.fill()
  screen.level(trigIndicator[3] and 15 or 1)
  screen.circle(118, 6, 1)
  screen.fill()
  screen.level(trigIndicator[4] and 15 or 1)
  screen.circle(123, 6, 1)
  screen.fill()
 
  screen.level(15)
  screen.move(((pageMode >= 6 and pageMode <= 9) and 2 or 3), 6)
  screen.text((pageMode >= 6 and pageMode <= 9) and "ALL" or "T:"..currtrack)
 
end

function draw_header_text(data)
  screen.move(64, 6)
  screen.text_center(data)

end

function draw_recplay()
  local str = ""
  draw_header_text(pages[pageMode].title)
 
  -- bignum
  if #tracks[currtrack].seq == 0 then
    str = "E"
  elseif recording then
    if recMode == 1 then
      str = #tracks[currtrack].seq
    elseif recMode == 2 or recMode == 3 then
      str = tracks[currtrack].seqIdx
    end
  elseif tracks[currtrack].seqIdx == 0 then
    str = "-"
  else
    str = tracks[currtrack].seqIdx
  end
  screen.move(64, 40)
  screen.aa(1)
  screen.font_face(3)
  screen.font_size(35)
  screen.text_center(str)
  screen.aa(0)
  screen.font_face(1)
  screen.font_size(8)

  -- recording indicator
  screen.move(75, 40)
  if recFlash then
    screen.level(15)
    str = "RECORDING..."
    screen.move(64-screen.text_extents(str)/2, 50)
    screen.text(str)
  end
 
  --recording mode indicator
  if recording and playing and #tracks[currtrack].seq > 0 and not tracks[currtrack].newRecording then
    screen.level(15)
    str = "Mode:"
    screen.move(128 - (screen.text_extents(str)), 30)
    screen.text(str)
    str = recModes[recMode]
    screen.move(128 - (screen.text_extents(str)), 37)
    screen.text(str)
   
  end
 
  if not recording then
    screen.move(1, 30)
    screen.text("Shift:")
    screen.move(1, 37)
    screen.text(tracks[currtrack].pitchShift.." st")
 
    str = "Length:"
    screen.move(128 - (screen.text_extents(str)), 30)
    screen.text(str)
    str = tostring(tracks[currtrack].length)
    screen.move(128 - (screen.text_extents(str)), 37)
    screen.text(str)
  
    screen.level(3)
    screen.move(64, 52)
    screen.text_center("Pattern "..currpattern)
  
  end  
 
end

function rec_message()
  while true do
    recFlash = true
    redraw()
    clock.sleep(0.4)
    recFlash = false
    redraw()
    clock.sleep(0.4)
  end
 
end

function flash_message(mode)
  for i = 1, 3 do
    if mode == "save" then saveFlash = true
      elseif mode == "load" then loadFlash = true
      elseif mode == "buffer" then bufferFlash = true
      elseif mode == 'edit' then editFlash = true
      elseif mode == 'pattern' then patternFlash = true
    end  
    redraw()
    clock.sleep(0.4)
    if mode == "save" then saveFlash = false
      elseif mode == "load" then loadFlash = false
      elseif mode == "buffer" then bufferFlash = false
      elseif mode == "edit" then editFlash = false
      elseif mode == 'pattern' then patternFlash = false
    end  
    redraw()
    clock.sleep(0.4)
  end
   
end

function draw_edit()
  local str = ""
  draw_header_text(pages[pageMode].title)
  
  -- bignum
  if #tracks[currtrack].seq == 0 then
    str = "E"
  elseif tracks[currtrack].seqIdx == 0 then
    str = "-"
  else
    str = tracks[currtrack].seqIdx
  end
  screen.move(64-(screen.text_extents(str)/2), 40)
  screen.aa(1)
  screen.font_face(3)
  screen.font_size(35)
  screen.text_center(str)
  screen.aa(0)
  screen.font_face(1)
  screen.font_size(8)

  screen.move(75, 40)
  if editFlash then
    screen.level(15)
    str = "** Pitch Updated! **"
    screen.move(64-screen.text_extents(str)/2, 50)
    screen.text(str)
  else
    -- display each note stored for this step
    str = ""
    if tracks[currtrack].seqIdx ~= 0 then    
      for i = 1, #tracks[currtrack].seq[tracks[currtrack].seqIdx].notes do
        if i > 1 then str = str.."-" end
        str = str..mu.note_num_to_name(tracks[currtrack].seq[tracks[currtrack].seqIdx].notes[i][1], true)
      end
    end
    screen.move(64-screen.text_extents(str)/2, 50)
    screen.text(str)
  end
 
  screen.move(1, 30)
  screen.text("Edit:")
  screen.move(1, 37)
  if #tracks[currtrack].seq > 0 then --this goofy check is for when we move into edit mode with an emtpy track selected
    screen.text(shift and (#tracks[currtrack].seq[tracks[currtrack].seqIdx].notes > 1 and "inv" or "oct") or "st")
  else
    screen.text("st")
  end
  
  str = "Select"
  screen.move(128 - (screen.text_extents(str)), 30)
  screen.text(str)
  str = "step"
  screen.move(128 - (screen.text_extents(str)), 37)
  screen.text(str)

end


function draw_trigs()
    draw_header_text(pages[pageMode].title)
   
    screen.level(paramSel == 1 and 15 or 3)
    screen.move(16, 20)
    screen.text("Select: "..tracks[currtrack].trigSel)
    screen.move (75, 20)
    screen.text("Length: "..tracks[currtrack].trigsLen)
 
    screen.level(paramSel == 2 and 15 or 3)
    screen.move(16, 30)
    screen.text("Slop: "..tracks[currtrack].trigs[tracks[currtrack].trigSel].slop)
    screen.move (75, 30)
    screen.text("Prob: "..tracks[currtrack].trigs[tracks[currtrack].trigSel].prob.."%")
 
    screen.level(paramSel == 3 and 15 or 3)
    screen.move(16, 40)
    screen.text("Gate: "..string.format("%.2f", tracks[currtrack].gate))
    screen.move (75, 40)
    screen.text("Rate: "..tracks[currtrack].rateStr)
 
    val = 6
    start = 5
    for i = 1, 16 do
      if tracks[currtrack].trigIdx == i and playing then
        screen.level(15)
      elseif tracks[currtrack].trigs[i].state then
        screen.level(5)
      else
        screen.level(1)
      end
      if tracks[currtrack].trigsLen >= i then
        screen.rect((i*8+3)-9, 46, val, val)
        screen.stroke()
        if tracks[currtrack].trigSel == i then
          screen.move((i*8+3)-9, 43)
          screen.level(15)
          screen.line(((i*8+3)+5)-9, 43)
          screen.stroke()
        end
      else
        screen.level(1)
        screen.move((i*8+3)-9, 49)
        screen.line(((i*8+3)+5)-9, 49)
        screen.stroke()
      end
    end
   
end

function draw_euclidian_trigs()
  draw_header_text(pages[pageMode].title)
 
  screen.level(paramSel == 1 and 15 or 3)
  screen.move(16, 20)
  screen.text("Triggers: "..tracks[currtrack].n)
  screen.move (75, 20)
  screen.text("Length: "..tracks[currtrack].k)

  screen.level(paramSel == 2 and 15 or 3)
  screen.move(16, 30)
  screen.text("Rotate: "..tracks[currtrack].erTrigRotation)
  screen.move (75, 30)
  screen.text("Prob: "..tracks[currtrack].erProb.."%")

  screen.level(paramSel == 3 and 15 or 3)
  screen.move(16, 40)
  screen.text("Gate: "..tracks[currtrack].gate)
  screen.move (75, 40)
  screen.text("Rate: "..tracks[currtrack].rateStr)

  val = 6
  start = 5
  for i = 1, 16 do
    if tracks[currtrack].erTrigIdx == i and tracks[currtrack].n > 0 and playing then
      screen.level(15)
    elseif tracks[currtrack].erTrigs[i] then
      screen.level(5)
    else
      screen.level(1)
    end
    if tracks[currtrack].k >= i then
      screen.rect((i*8+3)-9, 46, val, val)
      screen.stroke()
    else
      screen.level(1)
      screen.move((i*8+3)-9, 49)
      screen.line(((i*8+3)+5)-9, 49)
      screen.stroke()
    end
  end
 
end

function draw_transpositions()
    draw_header_text(pages[pageMode].title)
   
    screen.level(paramSel == 1 and 15 or 3)
    screen.move(16, 20)
    screen.text("Select: "..tracks[currtrack].transSel)
    screen.move (75, 20)
    screen.text("Shift: "..tracks[currtrack].transpose[tracks[currtrack].transSel])
 
    screen.level(paramSel == 2 and 15 or 3)
    screen.move(16, 30)
    screen.text("Length: "..tracks[currtrack].transLength)
    screen.move (75, 30)
    screen.text("When: "..(tracks[currtrack].transWhen > 0 and tracks[currtrack].transWhen or "End"))
 
    row = 42
    for i = 1, 8 do
      if i > 4 then row = 52 end
      screen.move(((((i-1)%4)*25)+4)+22, row)
      if i <= tracks[currtrack].transLength then
        screen.level((tracks[currtrack].transSel == i) and 15 or 3)
        if tracks[currtrack].transIdx == i then
          screen.text_center("[ "..tracks[currtrack].transpose[i].." ]")
        else
          screen.text_center(tracks[currtrack].transpose[i])
        end
      else
        screen.level(3)
        screen.text_center("...")
      end
    end
    
    screen.level(3)
    
    screen.move(10, 34)
    screen.line(118, 34)
   
    screen.move(11, 34)
    screen.line(11, 55)

    screen.move(118, 34)
    screen.line(118, 55)
   
    screen.stroke()
     
end

function draw_synth_edit()
    local oscOptions = {"Tri", "Saw", "Pulse"}

    draw_header_text(pages[pageMode].title)
   
    screen.level(paramSel == 1 and 15 or 3)
    screen.move(15, 20)
    screen.text("Wave: "..oscOptions[params:get("osc_wave_shape")])
    screen.move (77, 20)
    screen.text("Sub: "..string.format("%.2f", params:get("sub_osc_level")))
 
    screen.level(paramSel == 2 and 15 or 3)
    screen.move(15, 30)
    screen.text("PWM: "..string.format("%.2f", params:get("pulse_width_mod")))
    screen.move (77, 30)
    screen.text("Spd: "..string.format("%.2f", params:get("lfo_freq")))
 
    screen.level(paramSel == 3 and 15 or 3)
    screen.move(15, 40)
    screen.text("Freq: "..string.format("%.2f", params:get("lp_filter_cutoff")))
    screen.move (77, 40)
    screen.text("Res: "..string.format("%.2f", params:get("lp_filter_resonance")))

    screen.level(paramSel == 4 and 15 or 3)
    screen.move(15, 50)
    screen.text("Attk: "..string.format("%.2f", params:get("env_2_attack")))
    screen.move (77, 50)
    screen.text("Rls: "..string.format("%.2f", params:get("env_2_release")))
 

end


function draw_outputs()
    local options = {"Both", "MIDI", "Synth"}

    draw_header_text(pages[pageMode].title)
   
    screen.level(paramSel == 1 and 15 or 3)
    screen.move(4, 20)
    screen.text("T1")
    screen.move(25, 20)
    screen.text("Out: "..options[params:get("track_1_output")])
    screen.move (80, 20)
    screen.text("MIDI Ch: "..params:get("mchan_t1"))
 
    screen.level(paramSel == 2 and 15 or 3)
    screen.move(4, 30)
    screen.text("T2")
    screen.move(25, 30)
    screen.text("Out: "..options[params:get("track_2_output")])
    screen.move (80, 30)
    screen.text("MIDI Ch: "..params:get("mchan_t2"))
 
    screen.level(paramSel == 3 and 15 or 3)
    screen.move(4, 40)
    screen.text("T3")
    screen.move(25, 40)
    screen.text("Out: "..options[params:get("track_3_output")])
    screen.move (80, 40)
    screen.text("MIDI Ch: "..params:get("mchan_t3"))

    screen.level(paramSel == 4 and 15 or 3)
    screen.move(4, 50)
    screen.text("T4")
    screen.move(25, 50)
    screen.text("Out: "..options[params:get("track_4_output")])
    screen.move (80, 50)
    screen.text("MIDI Ch: "..params:get("mchan_t4"))
 
end


function draw_load_save()
    draw_header_text(pages[pageMode].title)
    screen.move(64, 20)
    screen.text_center("Current File: ")
    screen.move(64, 30)
    screen.text_center(currFile)
  
    if saveFlash then
      load_save_message("** File Saved! **")
    end

    if loadFlash then
      load_save_message("** File Loaded! **")
    end

    if bufferFlash then
      load_save_message("** Buffer Cleared! **")
    end

end

function load_save_message(msg)
  screen.level(15)
  screen.move(64, 45)
  screen.text_center(msg)
  
end

function draw_patterns()
    draw_header_text(pages[pageMode].title)
   
    screen.level(paramSel == 1 and 15 or 3)
    screen.move(16, 20)
    screen.text("Select: "..nextpattern)

    screen.move(64, 31)
    screen.level(patternFlash and 15 or 3)
    screen.text_center("Now Playing "..currpattern)
 
    row = 42
    for i = 1, 8 do
      if i > 4 then row = 52 end
      screen.move(((((i-1)%4)*25)+26), row) 
      screen.level((currpattern == i) and 15 or 3)
      if nextpattern == i then
        screen.text_center("[ "..i.." ]")
      else
        screen.text_center(i)
      end
    end
   
    screen.level(3)
    
    screen.move(10, 24)
    screen.line(118, 24)
    
    screen.move(11, 24)
    screen.line(11, 34)
    
    screen.move(118, 24)
    screen.line(118, 34)
    
    screen.move(10, 34)
    screen.line(118, 34)
   
    screen.move(11, 34)
    screen.line(11, 55)

    screen.move(118, 34)
    screen.line(118, 55)
   
    screen.stroke()
     
end


function draw_footer()
  screen.level(3)
  screen.move(0, 56)
  screen.line(128, 56)
  screen.stroke()
 
end


function draw_footer_text()
  local str = ""
  local str_L = ""
  local str_R = ""
  screen.level(15)
 
  if pageMode == 1 then
    str_L = "K2: Play Step"
    str_R = "K3:"..(shift and " Rec On" or " Play")
  elseif pageMode == 2 then
    if shift then
      str_L = "K2: Clear"
      str_R = "K3: "..(recording and "Rec Off" or "Rec On")
    else
      if not recording then
        str_L = "K2: "..(tracks[currtrack].mute and "Unmute" or "Mute")
      end
      if recording then
        if recMode == 1 and #tracks[currtrack].seq > 0 then
          str_L = "K2: Undo Last"
        end
        str_R = "K3: Rec Off"
      elseif playing then
        str_R = "K3: Stop"
      else
        str_R = "K3: Play"
      end
    end
  elseif pageMode == 3 then
    str_L = "K2: "..(shift and "Params (up)" or "Params")
    str_R = "K3: "..(shift and "Delete" or "Add")
  elseif pageMode == 4 then
    str_L = "K2: "..(shift and "Params (up)" or "Params")
    str_R = "K3: "..(tracks[currtrack].erMute and "Unmute" or "Mute")
  elseif pageMode == 5 then
    str_L = "K2: "..(shift and "Params (up)" or "Params")
    str_R = "K3: "..(tracks[currtrack].transMute and "Unmute" or "Mute")
  elseif pageMode == 6 or pageMode == 7 then
    str_L = "K2: "..(shift and "Params (up)" or "Params")
  elseif pageMode == 8 then
    str_L = "K2:"..(shift and " Clear Buffer" or " Load")  
    str_R = "K3: Save"
  elseif pageMode == 9 then
    str_L = "K2: "..(currpattern <= 7 and (shift and "Copy >>") or "Load")
    str_R = "K3: "..(shift and "Home" or (playing and "Stop" or "Play"))
  end
 
  screen.move(1, 62)
  screen.text(str_L)  
  screen.move(128-screen.text_extents(str_R), 62)
  screen.text(str_R)

end

function t_deepcopy(obj, seen)
  if type(obj) ~= 'table' then return obj end
  if seen and seen[obj] then
    return seen[obj]
  end

  local s = seen or {}
  local res = {}
  s[obj] = res
  for k, v in pairs(obj) do
    res[t_deepcopy(k, s)] = t_deepcopy(v, s)
  end
  return setmetatable(res, getmetatable(obj))

end
