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

package watchers;


import openfl.display.Sprite;
import openfl.events.*;
import openfl.utils.*;
import openfl.text.*;
import uiwidgets.*;
import util.Color;

class ListCell extends Sprite
{

	private var format : TextFormat = new TextFormat(CSS.font, 11, 0xFFFFFF, true);
	private static var normalColor : Int = Specs.listColor;
	private static var focusedColor : Int = Color.mixRGB(Color.scaleBrightness(Specs.listColor, 2), 0xEEEEEE, 0.6);

	public var tf : TextField;
	private var frame : ResizeableFrame;
	private var deleteButton : IconButton;
	private var deleteItem : Dynamic->Void;

	public function new(s : String, width : Int, whenChanged : Dynamic->Void, keyPress : Dynamic->Void, deleteItem : Dynamic->Void)
	{
		super();
		frame = new ResizeableFrame(0xFFFFFF, normalColor, 6, true);
		addChild(frame);
		addTextField(whenChanged, keyPress);
		tf.text = s;
		deleteButton = new IconButton(deleteItem, "deleteItem");
		setWidth(width);
	}

	public function setText(s : String, w : Int = 0) : Void{
		// Set the text and, optionally, the width.
		tf.text = s;
		setWidth(((w > 0)) ? w : frame.w);
		removeDeleteButton();
	}

	public function setEditable(isEditable : Bool) : Void{
		tf.type = (isEditable) ? TextFieldType.INPUT : TextFieldType.DYNAMIC;
	}

	public function setWidth(w : Int) : Void{
		tf.width = Math.max(w, 15);  // forces line wrapping, possibly changing tf.height  
		var frameH : Int = Std.int(Math.max(tf.textHeight + 7, 20));
		frame.setWidthHeight(Std.int(tf.width), frameH);
		deleteButton.x = tf.width - deleteButton.width - 3;
		deleteButton.y = (frameH - deleteButton.height) / 2;
	}

	private function addTextField(whenChanged : Dynamic->Void, keyPress : Dynamic->Void) : Void{
		tf = new TextField();
		tf.type = TextFieldType.INPUT;
		tf.wordWrap = true;
		tf.autoSize = TextFieldAutoSize.LEFT;
		tf.defaultTextFormat = format;
		tf.x = 3;
		tf.y = 1;
		tf.tabEnabled = false;
		tf.tabIndex = 1;
		tf.addEventListener(Event.CHANGE, whenChanged);
		tf.addEventListener(KeyboardEvent.KEY_DOWN, keyPress);
		tf.addEventListener(FocusEvent.FOCUS_IN, focusChange);
		tf.addEventListener(FocusEvent.FOCUS_OUT, focusChange);
		addChild(tf);
	}

	public function select() : Void{
		stage.focus = tf;
		tf.setSelection(0, tf.text.length);
		if (tf.type == TextFieldType.INPUT)             addDeleteButton();
	}

	private function focusChange(e : FocusEvent) : Void{
		var hasFocus : Bool = e.type == FocusEvent.FOCUS_IN && tf.type == TextFieldType.INPUT;
		frame.setColor((hasFocus) ? focusedColor : normalColor);
		tf.textColor = (hasFocus) ? 0 : 0xFFFFFF;
		haxe.Timer.delay((hasFocus) ? addDeleteButton : removeDeleteButton, 1);
	}

	private function removeDeleteButton() : Void{
		if (deleteButton.parent != null)             removeChild(deleteButton);
	}

	private function addDeleteButton() : Void{
		addChild(deleteButton);
		deleteButton.turnOff();
	}
}
