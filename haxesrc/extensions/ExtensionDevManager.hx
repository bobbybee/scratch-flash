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

package extensions;
import flash.events.*;
import flash.net.*;
import haxe.Timer;
//import flash.utils.clearInterval;
//import flash.utils.setInterval;

import translation.Translator;

import uiwidgets.Button;
import uiwidgets.DialogBox;

class ExtensionDevManager extends ExtensionManager {

	public var localExt:ScratchExtension = null;
	public var localFilePoller:Timer = null;
//	public var localFilePoller:Uint = 0;
	private var localFileRef:FileReference;

	public function ExtensionDevManager(app:Scratch) {
		super(app);
	}

	public function getLocalFileName(ext:ScratchExtension = null):String {
		if (localFileRef && (ext == localExt || ext == null)) return localFileRef.name;

		return null;
	}

	public function isLocalExtensionDirty(ext:ScratchExtension = null):Bool {
		return (!ext || ext == localExt) && localExt && localFileDirty;
	}

	// Override so that we can keep the reference to the local extension
	private var rawExtensionLoaded:Bool = false;

	override public function loadRawExtension(extObj:Dynamic):ScratchExtension {
		var ext:ScratchExtension = extensionDict[extObj.extensionName];
		var isLocalExt:Bool = (localExt && ext == localExt) || (localFilePoller && !localExt);
		ext = super.loadRawExtension(extObj);
		if (isLocalExt) {
			if (!localExt) {
				DialogBox.notify('Extensions', 'Your local extension "' + ext.name +
						'" is now loaded.The editor will notice when ' + localFileRef.name +
						' is\nsaved and offer you to reload the extension. Reloading an extension will stop the project.');
			}
			localExt = ext;
			localExtensionLoaded();
			app.updatePalette();
			app.setSaveNeeded();
		}

		rawExtensionLoaded = true;
		return ext;
	}

	private function localExtensionLoaded():Void {
	}

	public function makeLoadExperimentalExtensionButton():Button {
		function showShiftMenu(evt:MouseEvent):Void {
			loadAndWatchExtensionFile();
		}

		// TODO: button tip link
		var button:Button = new Button(Translator.map('Load Experimental Extension'));
/*
		if (SCRATCH::allow3d) { // TODO: use a better flag or rename this one
			// This event is only available in flash 11.2 and above.
			button.addEventListener(MouseEvent.RIGHT_CLICK, showShiftMenu);
		}
*/		
		button.setEventAction(function (evt:MouseEvent):Void {
			if (evt.shiftKey) {
				showShiftMenu(evt);
			} else {
				Scratch.app.setModalOverlay(true);
				Scratch.app.externalCall('JSshowExtensionDialog');
			}
		});

		return button;
	}

	// -----------------------------
	// Javascript Extension Development
	//------------------------------

	private var localFileDirty:Bool;

	public function loadAndWatchExtensionFile(ext:ScratchExtension = null):Void {
		if (localExt || localFilePoller > 0) {
			var msg:String = 'Sorry, a new extension cannot be created while another extension is connected to a file. ' +
					'Please save the project and disconnect from ' + localFileRef.name + ' first.';
			DialogBox.notify('Extensions', msg);
			return;
		}

		var filter:FileFilter = new FileFilter('Scratch 2.0 Javascript Extension', '*.js');
		var self:ExtensionDevManager = this;
		Scratch.loadSingleFile(function (e:Event):Void {
			FileReference(e.target).removeEventListener(Event.COMPLETE, arguments.callee);
			FileReference(e.target).addEventListener(Event.COMPLETE, self.extensionFileLoaded);
			self.localExt = ext;
			self.extensionFileLoaded(e);
		}, filter);
	}

	public function stopWatchingExtensionFile():Void {
		if (localFilePoller) { localFilePoller.stop(); localFilePoller = null;}
		localExt = null;
		localFilePoller = null;
		localFileDirty = false;
		localFileRef = null;
		localExtCodeDate = null;
		app.updatePalette();
	}

	private var localExtCodeDate:Date = null;

	private function extensionFileLoaded(e:Event):Void {
		localFileRef = FileReference(e.target);
		var lastModified:Date = localFileRef.modificationDate;
		var self:ExtensionDevManager = this;
		localFilePoller = new Timer(200);
		localFilePoller.run = function ():Void {
			if (lastModified.getTime() != self.localFileRef.modificationDate.getTime()) {
				lastModified = self.localFileRef.modificationDate;
				self.localFileDirty = true;
				clearInterval(self.localFilePoller);
				// Shutdown the extension
				self.localFileRef.load();
			}
		};

		if (localFileDirty && localExt) {
			//DialogBox.confirm('Reload the "' + localExt.name + '" from ' + localFileRef.name + '?', null, loadLocalCode);
			app.updatePalette();
		}
		else
			loadLocalCode();
	}

	public function getLocalCodeDate():Date {
		return localExtCodeDate;
	}

	public function loadLocalCode(db:DialogBox = null):Void {
		Scratch.app.runtime.stopAll();

		if (localExt) app.externalCall('ScratchExtensions.unregister', null, localExt.name);

		localFileDirty = false;
		rawExtensionLoaded = false;
		localExtCodeDate = localFileRef.modificationDate;
		app.externalCall('ScratchExtensions.loadLocalJS', null, localFileRef.data.toString());
//		if(!rawExtensionLoaded)
//			DialogBox.notify('Extensions', 'There was a problem loading your extension code. Please check your javascript console and fix the code.');

		app.updatePalette();
	}

	override public function setEnabled(extName:String, flag:Bool):Void {
		var ext:ScratchExtension = extensionDict[extName];
		if (ext && localExt == ext && !flag) {
			stopWatchingExtensionFile();
		}

		super.setEnabled(extName, flag);
	}

	public function getExperimentalExtensionNames():Array<Dynamic> {
		var names:Array<Dynamic> = [];
		for (Std.is(ext, extensionDict)) {
			if (!ext.isInternal && ext.javascriptURL) {
				names.push(ext.name);
			}
		}
		return names;
	}
}

