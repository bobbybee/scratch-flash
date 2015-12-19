/*
 * Scratch Project Editor and Player
 * Copyright (C) 2014 Massachusetts Institute of Technology
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

// SoundPrimitives.as
// John Maloney, June 2010
//
// Sound primitives.

package primitives;

import primitives.NotePlayer;
import primitives.Scratch;
import primitives.ScratchSound;
import primitives.ScratchSoundPlayer;
import primitives.Thread;

import blocks.Block;
import flash.utils.Dictionary;
import interpreter.*;
import scratch.*;
import sound.*;

class SoundPrims
{
    
    private var app : Scratch;
    private var interp : Interpreter;
    
    public function new(app : Scratch, interpreter : Interpreter)
    {
        this.app = app;
        this.interp = interpreter;
    }
    
    public function addPrimsTo(primTable : Dictionary) : Void{
        Reflect.setField(primTable, "playSound:", primPlaySound);
        Reflect.setField(primTable, "doPlaySoundAndWait", primPlaySoundUntilDone);
        Reflect.setField(primTable, "stopAllSounds", function(b : Dynamic) : Dynamic{ScratchSoundPlayer.stopAllSounds();
        });
        
        Reflect.setField(primTable, "drum:duration:elapsed:from:", primPlayDrum);  // Scratch 1.4 drum numbers  
        Reflect.setField(primTable, "playDrum", primPlayDrum);
        Reflect.setField(primTable, "rest:elapsed:from:", primPlayRest);
        
        Reflect.setField(primTable, "noteOn:duration:elapsed:from:", primPlayNote);
        Reflect.setField(primTable, "midiInstrument:", primSetInstrument);  // Scratch 1.4 instrument numbers  
        Reflect.setField(primTable, "instrument:", primSetInstrument);
        
        Reflect.setField(primTable, "changeVolumeBy:", primChangeVolume);
        Reflect.setField(primTable, "setVolumeTo:", primSetVolume);
        Reflect.setField(primTable, "volume", primVolume);
        
        Reflect.setField(primTable, "changeTempoBy:", function(b : Dynamic) : Dynamic{
            app.stagePane.setTempo(app.stagePane.tempoBPM + interp.numarg(b, 0));
            interp.redraw();
        });
        Reflect.setField(primTable, "setTempoTo:", function(b : Dynamic) : Dynamic{
            app.stagePane.setTempo(interp.numarg(b, 0));
            interp.redraw();
        });
        Reflect.setField(primTable, "tempo", function(b : Dynamic) : Dynamic{return app.stagePane.tempoBPM;
        });
    }
    
    private function primPlaySound(b : Block) : Void{
        var snd : ScratchSound = interp.targetObj().findSound(interp.arg(b, 0));
        if (snd != null)             playSound(snd, interp.targetObj());
    }
    
    private function primPlaySoundUntilDone(b : Block) : Void{
        var activeThread : Thread = interp.activeThread;
        if (activeThread.firstTime) {
            var snd : ScratchSound = interp.targetObj().findSound(interp.arg(b, 0));
            if (snd == null)                 return;
            activeThread.tmpObj = playSound(snd, interp.targetObj());
            activeThread.firstTime = false;
        }
        var player : ScratchSoundPlayer = cast((activeThread.tmpObj), ScratchSoundPlayer);
        if ((player == null) || (player.atEnd())) {  // finished playing  
            activeThread.tmp = 0;
            activeThread.firstTime = true;
        }
        else {
            interp.doYield();
        }
    }
    
    private function primPlayNote(b : Block) : Void{
        var s : ScratchObj = interp.targetObj();
        if (s == null)             return;
        if (interp.activeThread.firstTime) {
            var key : Float = interp.numarg(b, 0);
            var secs : Float = beatsToSeconds(interp.numarg(b, 1));
            interp.activeThread.tmpObj = playNote(s.instrument, key, secs, s);
            interp.startTimer(secs);
        }
        else {
            interp.checkTimer();
        }
    }
    
    private function primPlayDrum(b : Block) : Void{
        var s : ScratchObj = interp.targetObj();
        if (s == null)             return;
        if (interp.activeThread.firstTime) {
            var drum : Int = Math.round(interp.numarg(b, 0));
            var isMIDI : Bool = (b.op == "drum:duration:elapsed:from:");
            var secs : Float = beatsToSeconds(interp.numarg(b, 1));
            playDrum(drum, isMIDI, 10, s);  // always play entire drum sample  
            interp.startTimer(secs);
        }
        else {
            interp.checkTimer();
        }
    }
    
    private function playSound(s : ScratchSound, client : ScratchObj) : ScratchSoundPlayer{
        var player : ScratchSoundPlayer = s.sndplayer();
        player.client = client;
        player.startPlaying();
        return player;
    }
    
    private function playDrum(drum : Int, isMIDI : Bool, secs : Float, client : ScratchObj) : ScratchSoundPlayer{
        var player : NotePlayer = SoundBank.getDrumPlayer(drum, isMIDI, secs);
        if (player == null)             return null;
        player.client = client;
        player.setDuration(secs);
        player.startPlaying();
        return player;
    }
    
    private function playNote(instrument : Int, midiKey : Float, secs : Float, client : ScratchObj) : ScratchSoundPlayer{
        var player : NotePlayer = SoundBank.getNotePlayer(instrument, midiKey);
        if (player == null)             return null;
        player.client = client;
        player.setNoteAndDuration(midiKey, secs);
        player.startPlaying();
        return player;
    }
    
    private function primPlayRest(b : Block) : Void{
        var s : ScratchObj = interp.targetObj();
        if (s == null)             return;
        if (interp.activeThread.firstTime) {
            var secs : Float = beatsToSeconds(interp.numarg(b, 0));
            interp.startTimer(secs);
        }
        else {
            interp.checkTimer();
        }
    }
    
    private function beatsToSeconds(beats : Float) : Float{
        return (beats * 60) / app.stagePane.tempoBPM;
    }
    
    private function primSetInstrument(b : Block) : Void{
        // Set Scratch 2.0 instrument.
        var instr : Int = interp.numarg(b, 0) - 1;
        if (b.op == "midiInstrument:") {
            // map old to new instrument number
            instr = instrumentMap[instr] - 1;
        }
        instr = Math.max(0, Math.min(instr, SoundBank.instrumentNames.length - 1));
        if (interp.targetObj())             interp.targetObj().instrument = instr;
    }
    
    private function primChangeVolume(b : Block) : Void{
        var s : ScratchObj = interp.targetObj();
        if (s != null) {
            s.setVolume(s.volume + interp.numarg(b, 0));
            interp.redraw();
        }
    }
    
    private function primSetVolume(b : Block) : Void{
        var s : ScratchObj = interp.targetObj();
        if (s != null) {
            s.setVolume(interp.numarg(b, 0));
            interp.redraw();
        }
    }
    
    private function primVolume(b : Block) : Float{
        var s : ScratchObj = interp.targetObj();
        return ((s != null)) ? s.volume : 0;
    }
    
    // Map from a Scratch 1.4 (i.e. MIDI) instrument number to the closest Scratch 2.0 equivalent.
    private var instrumentMap : Array<Dynamic> = [
        // Acoustic Grand, Bright Acoustic, Electric Grand, Honky-Tonk
        1, 1, 1, 1, 
        // Electric Piano 1, Electric Piano 2, Harpsichord, Clavinet
        2, 2, 4, 4, 
        // Celesta, Glockenspiel, Music Box, Vibraphone
        17, 17, 17, 16, 
        // Marimba, Xylophone, Tubular Bells, Dulcimer
        19, 16, 17, 17, 
        // Drawbar Organ, Percussive Organ, Rock Organ, Church Organ
        3, 3, 3, 3, 
        // Reed Organ, Accordion, Harmonica, Tango Accordion
        3, 3, 3, 3, 
        // Nylon String Guitar, Steel String Guitar, Electric Jazz Guitar, Electric Clean Guitar
        4, 4, 5, 5, 
        // Electric Muted Guitar, Overdriven Guitar,Distortion Guitar, Guitar Harmonics
        5, 5, 5, 5, 
        // Acoustic Bass, Electric Bass (finger), Electric Bass (pick), Fretless Bass
        6, 6, 6, 6, 
        // Slap Bass 1, Slap Bass 2, Synth Bass 1, Synth Bass 2
        6, 6, 6, 6, 
        // Violin, Viola, Cello, Contrabass
        8, 8, 8, 8, 
        // Tremolo Strings, Pizzicato Strings, Orchestral Strings, Timpani
        8, 7, 8, 19, 
        // String Ensemble 1, String Ensemble 2, SynthStrings 1, SynthStrings 2
        8, 8, 8, 8, 
        // Choir Aahs, Voice Oohs, Synth Voice, Orchestra Hit
        15, 15, 15, 19, 
        // Trumpet, Trombone, Tuba, Muted Trumpet
        9, 9, 9, 9, 
        // French Horn, Brass Section, SynthBrass 1, SynthBrass 2
        9, 9, 9, 9, 
        // Soprano Sax, Alto Sax, Tenor Sax, Baritone Sax
        11, 11, 11, 11, 
        // Oboe, English Horn, Bassoon, Clarinet
        14, 14, 14, 10, 
        // Piccolo, Flute, Recorder, Pan Flute
        12, 12, 13, 13, 
        // Blown Bottle, Shakuhachi, Whistle, Ocarina
        13, 13, 12, 12, 
        // Lead 1 (square), Lead 2 (sawtooth), Lead 3 (calliope), Lead 4 (chiff)
        20, 20, 20, 20, 
        // Lead 5 (charang), Lead 6 (voice), Lead 7 (fifths), Lead 8 (bass+lead)
        20, 20, 20, 20, 
        // Pad 1 (new age), Pad 2 (warm), Pad 3 (polysynth), Pad 4 (choir)
        21, 21, 21, 21, 
        // Pad 5 (bowed), Pad 6 (metallic), Pad 7 (halo), Pad 8 (sweep)
        21, 21, 21, 21, 
        // FX 1 (rain), FX 2 (soundtrack), FX 3 (crystal), FX 4 (atmosphere)
        21, 21, 21, 21, 
        // FX 5 (brightness), FX 6 (goblins), FX 7 (echoes), FX 8 (sci-fi)
        21, 21, 21, 21, 
        // Sitar, Banjo, Shamisen, Koto
        4, 4, 4, 4, 
        // Kalimba, Bagpipe, Fiddle, Shanai
        17, 14, 8, 10, 
        // Tinkle Bell, Agogo, Steel Drums, Woodblock
        17, 17, 18, 19, 
        // Taiko Drum, Melodic Tom, Synth Drum, Reverse Cymbal
        1, 1, 1, 1, 
        // Guitar Fret Noise, Breath Noise, Seashore, Bird Tweet
        21, 21, 21, 21, 
        // Telephone Ring, Helicopter, Applause, Gunshot
        21, 21, 21, 21];
}
