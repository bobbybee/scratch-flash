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

// GestureHandler.as
// John Maloney, April 2010
//
// This class handles mouse gestures at a global level. While some UI widgets must
// do their own event handling, an object that only needs to respond to clicks or
// provide a contextual menu may do so simply by implementing one of these methods:
//
//		click()
//		doubleClick()
//		menu(evt)
//
// GestureHandler also supports mouse handling on objects such as sliders via
// the DragClient interface. This mechanism ensures that the widget will continue
// to receive mouse move events until the mouse goes up even if the mouse is moved
// away from the widget. This is useful because the native Flash mouse handling stops
// sending mouse events to an object if the mouse moves off that object.
//
// GestureHandler supports a simple drag-n-drop ("grab-n-drop") mechanism.
// To become draggable, an object merely needs to implement the method objToGrab().
// If that returns a DisplayObject, the object will be dragged until the mouse is released.
// If objToGrab() returns null no object is dragged. To become a drop target, an object
// implements the handleDrop() method. This method returns true if the dropped object is
// accepted, false if the drop is rejected. Dragged objects are provided with a drop shadow
// in editMode.
//
// For developers, if DEBUG is true then shift-click will highlight objects in the
// DisplayObject hierarchy and print their names in the console. This can be used to
// understand the nesting of UI objects.

package util;

import openfl.errors.Error;

import openfl.display.*;
import openfl.events.MouseEvent;
import openfl.filters.*;
import openfl.geom.*;
import openfl.text.*;

import blocks.*;
import scratch.*;
import uiwidgets.*;
import svgeditor.*;
import watchers.*;

class GestureHandler
{

	private static inline var DOUBLE_CLICK_MSECS : Int = 400;
	private var DEBUG : Bool = false;

	private static inline var SCROLL_RANGE : Float = 60;
	private var SCROLL_MAX_SPEED : Float = 1000 / 50;
	private static inline var SCROLL_MSECS : Int = 500;

	public var mouseIsDown : Bool;

	// Grab-n-drop support:
	public var carriedObj : Sprite;
	private var originalParent : DisplayObjectContainer;
	private var originalPosition : Point;
	private var originalScale : Float;

	private var app : Scratch;
	private var stage : Stage;
	private var dragClient : DragClient;
	private var mouseDownTime : Int;
	private var gesture : String = "idle";
	private var mouseTarget : Dynamic;
	private var objToGrabOnUp : Sprite;
	private var mouseDownEvent : MouseEvent;
	private var inIE : Bool;

	private var scrollTarget : ScrollFrame;
	private var scrollStartTime : Int;
	private var scrollXVelocity : Float;
	private var scrollYVelocity : Float;

	private var bubble : TalkBubble;
	private var bubbleStartX : Float;
	private var bubbleStartY : Float;
	private static var bubbleRange : Float = 25;
	private static var bubbleMargin : Float = 5;

	public function new(app : Scratch, inIE : Bool)
	{
		this.app = app;
		this.stage = app.stage;
		this.inIE = inIE;
	}

	public function setDragClient(newClient : DragClient, evt : MouseEvent) : Void{
		Menu.removeMenusFrom(stage);
		if (carriedObj != null)             return;
		if (dragClient != null)             dragClient.dragEnd(evt);
		dragClient = try cast(newClient, DragClient) catch(e:Dynamic) null;
		dragClient.dragBegin(evt);
		evt.stopImmediatePropagation();
	}

	public function grabOnMouseUp(obj : Sprite) : Void{
		if (CursorTool.tool == "copy") {
			// If duplicate tool, grab right away
			grab(obj, null);
			gesture = "drag";
		}
		else {
			objToGrabOnUp = obj;
		}
	}

	public function step() : Void{
		if ((Math.round(haxe.Timer.stamp() * 1000) - mouseDownTime) > DOUBLE_CLICK_MSECS) {
			if (gesture == "unknown") {
				if (mouseTarget != null)                     handleDrag(null);
				if (gesture != "drag")                     handleClick(mouseDownEvent);
			}
			if (gesture == "clickOrDoubleClick") {
				handleClick(mouseDownEvent);
			}
		}
		if (carriedObj != null && scrollTarget != null && (Math.round(haxe.Timer.stamp() * 1000) - scrollStartTime) > SCROLL_MSECS && (scrollXVelocity != 0 || scrollYVelocity != 0)) {
			scrollTarget.contents.x = Math.min(0, Math.max(-scrollTarget.maxScrollH(), scrollTarget.contents.x + scrollXVelocity));
			scrollTarget.contents.y = Math.min(0, Math.max(-scrollTarget.maxScrollV(), scrollTarget.contents.y + scrollYVelocity));
			scrollTarget.constrainScroll();
			scrollTarget.updateScrollbars();
			var b : Block = try cast(carriedObj, Block) catch(e:Dynamic) null;
			if (b != null) {
				app.scriptsPane.findTargetsFor(b);
				app.scriptsPane.updateFeedbackFor(b);
			}
		}
	}

	public function rightMouseClick(evt : MouseEvent) : Void{
		// You only get this event in AIR.
		rightMouseDown(Std.int(evt.stageX), Std.int(evt.stageY), false);
	}

	public function rightMouseDown(x : Int, y : Int, isChrome : Bool) : Void{
		// To avoid getting the Adobe menu on right-click, JavaScript captures
		// right-button mouseDown events and calls this method.'
		Menu.removeMenusFrom(stage);
		var menuTarget : DisplayObject = findTargetFor("menu", app, x, y);
		if (menuTarget == null)             return;
		var menu : Menu = null;
		try{menu = (cast menuTarget).menu(new MouseEvent("right click"));
		}        catch (e : Error){ };
		if (menu != null)             menu.showOnStage(stage, x, y);
		if (!isChrome)             Menu.removeMenusFrom(stage);  // hack: clear menuJustCreated because there's no rightMouseUp  ;
	}

	private function findTargetFor(property : String, obj : Dynamic, x : Int, y : Int) : DisplayObject {
		// Return the innermost child  of obj that contains the given (global) point
		// and implements the menu() method.
		if (Std.is(obj, Scratch))
		{
			var main: Scratch = cast(obj, Scratch);
			var i : Int = Std.int(main.numChildren - 1);
			while (i >= 0){
				var found : DisplayObject = findTargetFor(property, main.getChildAt(i), x, y);
				if (found != null)                     return found;
				i--;
			}
		}
		if (Std.is(obj, DisplayObject))
		{
			var dispObj: DisplayObject = obj;
			if (!dispObj.visible || !dispObj.hitTestPoint(x, y, true))
				return null;
			if (Std.is(dispObj, DisplayObjectContainer)) {
				var dispObjContainer: DisplayObjectContainer = cast(dispObj, DisplayObjectContainer);
				var i : Int = Std.int(dispObjContainer.numChildren - 1);
				while (i >= 0){
					var found : DisplayObject = findTargetFor(property, dispObjContainer.getChildAt(i), x, y);
					if (found != null)                     return found;
					i--;
				}
			}
		}
		
		return Compat.hasMethod(obj, property) ? obj : null;
	}

	public function mouseDown(evt : MouseEvent) : Void{
		//if (inIE && app.editMode && app.jsEnabled) 
			//app.externalCall("tip_bar_api.fixIE");

		evt.updateAfterEvent();  // needed to avoid losing display updates with later version of Flash 11  
		hideBubble();
		mouseIsDown = true;
		if (gesture == "clickOrDoubleClick") {
			handleDoubleClick(mouseDownEvent);
			return;
		}
		if (CursorTool.tool != null) {
			handleTool(evt);
			return;
		}
		mouseDownTime = Math.round(haxe.Timer.stamp() * 1000);
		mouseDownEvent = evt;
		gesture = "unknown";
		mouseTarget = null;

		if (carriedObj != null) {drop(evt);return;
		}

		if (dragClient != null) {
			dragClient.dragBegin(evt);
			return;
		}
		if (DEBUG && evt.shiftKey)             return showDebugFeedback(evt);

		var t : Dynamic = evt.target;
		if ((Std.is(t, TextField)) && (cast((t), TextField).type == TextFieldType.INPUT))             return;
		mouseTarget = findMouseTarget(evt, t);
		if (mouseTarget == null) {
			gesture = "ignore";
			return;
		}

		if (doClickImmediately()) {
			handleClick(evt);
			return;
		}
		if (evt.shiftKey && app.editMode && Compat.hasMethod(mouseTarget, "menu")) {
			gesture = "menu";
			return;
		}
	}

	private function doClickImmediately() : Bool{
		// Answer true when clicking on the stage or a locked sprite in play (presentation) mode.
		if (app.editMode)             return false;
		if (Std.is(mouseTarget, ScratchStage))             return true;
		return (Std.is(mouseTarget, ScratchSprite)) && !cast((mouseTarget), ScratchSprite).isDraggable;
	}

	public function mouseMove(evt : MouseEvent) : Void{
		if (gesture == "debug") {evt.stopImmediatePropagation();return;
		}
		mouseIsDown = evt.buttonDown;
		if (dragClient != null) {
			dragClient.dragMove(evt);
			return;
		}
		if (gesture == "unknown") {
			if (mouseTarget != null)                 handleDrag(evt);
			return;
		}
		if ((gesture == "drag") && (Std.is(carriedObj, Block))) {
			app.scriptsPane.updateFeedbackFor(cast((carriedObj), Block));
		}
		if ((gesture == "drag") && (Std.is(carriedObj, ScratchSprite))) {
			var stageP : Point = app.stagePane.globalToLocal(carriedObj.localToGlobal(new Point(0, 0)));
			var spr : ScratchSprite = cast((carriedObj), ScratchSprite);
			spr.scratchX = stageP.x - 240;
			spr.scratchY = 180 - stageP.y;
			spr.updateBubble();
		}
		var oldTarget : ScrollFrame = scrollTarget;
		scrollTarget = null;
		var targets : Array<Dynamic> = stage.getObjectsUnderPoint(new Point(stage.mouseX, stage.mouseY));
		for (t in targets){
			if (Std.is(t, ScrollFrameContents)) {
				scrollTarget = try cast(t.parent, ScrollFrame) catch(e:Dynamic) null;
				if (scrollTarget != oldTarget) {
					scrollStartTime = Math.round(haxe.Timer.stamp() * 1000);
				}
				break;
			}
		}
		if (scrollTarget != null) {
			var p : Point = scrollTarget.localToGlobal(new Point(0, 0));
			var mx : Int = Std.int(stage.mouseX);
			var my : Int = Std.int(stage.mouseY);
			var d : Float = mx - p.x;
			if (d >= 0 && d <= SCROLL_RANGE && scrollTarget.canScrollLeft()) {
				scrollXVelocity = (1 - d / SCROLL_RANGE) * SCROLL_MAX_SPEED;
			}
			else {
				d = p.x + scrollTarget.visibleW() - mx;
				if (d >= 0 && d <= SCROLL_RANGE && scrollTarget.canScrollRight()) {
					scrollXVelocity = (d / SCROLL_RANGE - 1) * SCROLL_MAX_SPEED;
				}
				else {
					scrollXVelocity = 0;
				}
			}
			d = my - p.y;
			if (d >= 0 && d <= SCROLL_RANGE && scrollTarget.canScrollUp()) {
				scrollYVelocity = (1 - d / SCROLL_RANGE) * SCROLL_MAX_SPEED;
			}
			else {
				d = p.y + scrollTarget.visibleH() - my;
				if (d >= 0 && d <= SCROLL_RANGE && scrollTarget.canScrollDown()) {
					scrollYVelocity = (d / SCROLL_RANGE - 1) * SCROLL_MAX_SPEED;
				}
				else {
					scrollYVelocity = 0;
				}
			}
			if (scrollXVelocity == 0 && scrollYVelocity == 0) {
				scrollStartTime = Math.round(haxe.Timer.stamp() * 1000);
			}
		}
		if (bubble != null) {
			var dx : Float = bubbleStartX - stage.mouseX;
			var dy : Float = bubbleStartY - stage.mouseY;
			if (dx * dx + dy * dy > bubbleRange * bubbleRange) {
				hideBubble();
			}
		}
	}

	public function mouseUp(evt : MouseEvent) : Void{
		if (gesture == "debug") {evt.stopImmediatePropagation();return;
		}
		mouseIsDown = false;
		if (dragClient != null) {
			var oldClient : DragClient = dragClient;
			dragClient = null;
			oldClient.dragEnd(evt);
			return;
		}
		drop(evt);
		Menu.removeMenusFrom(stage);
		if (gesture == "unknown") {
			if (mouseTarget != null && Compat.hasMethod(mouseTarget, "doubleClick"))                 
				gesture = "clickOrDoubleClick";
			else {
				handleClick(evt);
				mouseTarget = null;
				gesture = "idle";
			}
			return;
		}
		if (gesture == "menu")             handleMenu(evt);
		if (app.scriptsPane != null)             app.scriptsPane.draggingDone();
		mouseTarget = null;
		gesture = "idle";
		if (objToGrabOnUp != null) {
			gesture = "drag";
			grab(objToGrabOnUp, evt);
			objToGrabOnUp = null;
		}
	}

	public function mouseWheel(evt : MouseEvent) : Void{
		hideBubble();
	}

	public function escKeyDown() : Void{
		if (carriedObj != null && Std.is(carriedObj, Block)) {
			carriedObj.stopDrag();
			removeDropShadowFrom(carriedObj);
			cast((carriedObj), Block).restoreOriginalState();
			carriedObj = null;
		}
	}

	private function findMouseTarget(evt : MouseEvent, target : Dynamic) : DisplayObject{
		// Find the mouse target for the given event. Return null if no target found.

		if ((Std.is(target, TextField)) && (cast((target), TextField).type == TextFieldType.INPUT))             return null;
		if ((Std.is(target, Button)) || (Std.is(target, IconButton)))             return null;

		var o : DisplayObject = try cast(evt.target, DisplayObject) catch(e:Dynamic) null;
		var mouseTarget : Bool = false;
		while (o != null){
			if (isMouseTarget(o, Std.int(evt.stageX / app.scaleX), Std.int(evt.stageY / app.scaleY))) {
				mouseTarget = true;
				break;
			}
			o = o.parent;
		}
		var rect : Rectangle = app.stageObj().getRect(stage);
		if (!mouseTarget && rect.contains(evt.stageX, evt.stageY))             return findMouseTargetOnStage(Std.int(evt.stageX / app.scaleX), Std.int(evt.stageY / app.scaleY));
		if (o == null)             return null;
		if ((Std.is(o, Block)) && cast((o), Block).isEmbeddedInProcHat())             return o.parent;
		if (Std.is(o, ScratchObj))             return findMouseTargetOnStage(Std.int(evt.stageX / app.scaleX), Std.int(evt.stageY / app.scaleY));
		return o;
	}

	private function findMouseTargetOnStage(globalX : Int, globalY : Int) : DisplayObject{
		// Find the front-most, visible stage element at the given point.
		// Take sprite shape into account so you can click or grab a sprite
		// through a hole in another sprite that is in front of it.
		// Return the stage if no other object is found.
		if (app.isIn3D)             app.stagePane.visible = true;
		var o : DisplayObject;
		var uiLayer : Sprite = app.stagePane.getUILayer();
		var i : Int = uiLayer.numChildren - 1;
		while (i > 0){
			o = try cast(uiLayer.getChildAt(i), DisplayObject) catch(e:Dynamic) null;
			if (Std.is(o, Bitmap))                 break;  // hit the paint layer of the stage; no more elments  ;
			if (o.visible && o.hitTestPoint(globalX, globalY, true)) {
				if (app.isIn3D)                     app.stagePane.visible = false;
				return o;
			}
			i--;
		}
		if (app.stagePane != uiLayer) {
			i = app.stagePane.numChildren - 1;
			while (i > 0){
				o = try cast(app.stagePane.getChildAt(i), DisplayObject) catch(e:Dynamic) null;
				if (Std.is(o, Bitmap))                     break;  // hit the paint layer of the stage; no more elments  ;
				if (o.visible && o.hitTestPoint(globalX, globalY, true)) {
					if (app.isIn3D)                         app.stagePane.visible = false;
					return o;
				}
				i--;
			}
		}

		if (app.isIn3D)             app.stagePane.visible = false;
		return app.stagePane;
	}

	private function isMouseTarget(o : DisplayObject, globalX : Int, globalY : Int) : Bool{
		// Return true if the given object is hit by the mouse and has a
		// method named click, doubleClick, menu or objToGrab.
		if (!o.hitTestPoint(globalX, globalY, true))             return false;
		if ((Compat.hasMethod(o, "click")) || (Compat.hasMethod(o, "doubleClick")))             return true;
		if ((Compat.hasMethod(o, "menu")) || (Compat.hasMethod(o, "objToGrab")))             return true;
		return false;
	}

	private function handleDrag(evt : MouseEvent) : Void{
		// Note: Called with a null event if gesture is click and hold.
		Menu.removeMenusFrom(stage);
		if (!Compat.hasMethod(mouseTarget, "objToGrab"))             return;
		if (!app.editMode) {
			if (app.loadInProgress)                 return;
			if ((Std.is(mouseTarget, ScratchSprite)) && !cast((mouseTarget), ScratchSprite).isDraggable)                 return;  // don't drag locked sprites in presentation mode  ;
			if ((Std.is(mouseTarget, Watcher)) || (Std.is(mouseTarget, ListWatcher)))                 return;  // don't drag watchers in presentation mode  ;
		}
		grab(mouseTarget, evt);
		gesture = "drag";
		if (Std.is(carriedObj, Block)) {
			app.scriptsPane.updateFeedbackFor(cast((carriedObj), Block));
		}
	}

	private function handleClick(evt : MouseEvent) : Void{
		if (mouseTarget == null)             return;
		evt.updateAfterEvent();
		if (Compat.hasMethod(mouseTarget, "click"))             mouseTarget.click(evt);
		gesture = "click";
	}

	private function handleDoubleClick(evt : MouseEvent) : Void{
		if (mouseTarget == null)             return;
		if (Compat.hasMethod(mouseTarget, "doubleClick"))
			mouseTarget.doubleClick(evt);
		gesture = "doubleClick";
	}

	private function handleMenu(evt : MouseEvent) : Void{
		if (mouseTarget == null)             return;
		var menu : Menu = null;
		try{menu = mouseTarget.menu(evt);
		}        catch (e : Error){ };
		if (menu != null)             menu.showOnStage(stage, Std.int(evt.stageX / app.scaleX), Std.int(evt.stageY / app.scaleY));
	}

	private var lastGrowShrinkSprite : Sprite;

	private function handleTool(evt : MouseEvent) : Void{
		var isGrowShrink : Bool = ("grow" == CursorTool.tool) || ("shrink" == CursorTool.tool);
		var t : DisplayObject = findTargetFor("handleTool", app, Std.int(evt.stageX / app.scaleX), Std.int(evt.stageY / app.scaleY));
		if (t == null)             t = findMouseTargetOnStage(Std.int(evt.stageX / app.scaleX), Std.int(evt.stageY / app.scaleY));

		if (isGrowShrink && (Std.is(t, ScratchSprite))) {
			function clearTool(e : MouseEvent) : Void{
				if (lastGrowShrinkSprite != null) {
					lastGrowShrinkSprite.removeEventListener(MouseEvent.MOUSE_OUT, clearTool);
					lastGrowShrinkSprite = null;
					app.clearTool();
				}
			};
			if (lastGrowShrinkSprite == null && !evt.shiftKey) {
				t.addEventListener(MouseEvent.MOUSE_OUT, clearTool);
				lastGrowShrinkSprite = cast(t, ScratchSprite);
			}
			(cast t).handleTool(CursorTool.tool, evt);
			return;
		}
		if (t != null && Compat.hasMethod(t, "handleTool"))
			(cast t).handleTool(CursorTool.tool, evt);
		if (isGrowShrink && (Std.is(t, Block) && cast(t, Block).isInPalette() /*|| Std.is(t, ImageCanvas)*/))             return;  // grow/shrink sticky for scripting area  ;

		if (!evt.shiftKey)             app.clearTool();  // don't clear if shift pressed  ;
	}

	private function grab(obj : Sprite, evt : MouseEvent) : Void{
		// Note: Called with a null event if gesture is click and hold.
		if (evt != null)             drop(evt);

		var globalP : Point = obj.localToGlobal(new Point(0, 0));  // record the original object's global position  
		var untypedObj : Dynamic = obj;
		obj = untypedObj.objToGrab((evt != null) ? evt : new MouseEvent(""));  // can return the original object, a new object, or null  
		if (obj == null)             return;  // not grabbable  ;
		if (obj.parent != null)             globalP = obj.localToGlobal(new Point(0, 0));  // update position if not a copy  ;

		originalParent = obj.parent;  // parent is null if objToGrab() returns a new object  
		originalPosition = new Point(obj.x, obj.y);
		originalScale = obj.scaleX;

		if (Std.is(obj, Block)) {
			var b : Block = cast((obj), Block);
			b.saveOriginalState();
			if (Std.is(b.parent, Block))                 cast((b.parent), Block).removeBlock(b);
			if (b.parent != null)                 b.parent.removeChild(b);
			app.scriptsPane.prepareToDrag(b);
		}
		else if (Std.is(obj, ScratchComment)) {
			var c : ScratchComment = cast((obj), ScratchComment);
			if (c.parent != null)                 c.parent.removeChild(c);
			app.scriptsPane.prepareToDragComment(c);
		}
		else {
			var inStage : Bool = (obj.parent == app.stagePane);
			if (obj.parent != null) {
				if (Std.is(obj, ScratchSprite) && app.isIn3D) 
					cast(obj, ScratchSprite).prepareToDrag();

				obj.parent.removeChild(obj);
			}
			if (inStage && (app.stagePane.scaleX != 1)) {
				obj.scaleX = obj.scaleY = (obj.scaleX * app.stagePane.scaleX);
			}
		}

		if (app.editMode)             addDropShadowTo(obj);
		stage.addChild(obj);
		obj.x = globalP.x;
		obj.y = globalP.y;
		if (evt != null && mouseDownEvent != null) {
			obj.x += evt.stageX - mouseDownEvent.stageX;
			obj.y += evt.stageY - mouseDownEvent.stageY;
		}
		obj.startDrag();
		if (Std.is(obj, DisplayObject))             obj.cacheAsBitmap = true;
		carriedObj = obj;
		scrollStartTime = Math.round(haxe.Timer.stamp() * 1000);
	}

	private function dropHandled(droppedObj : Sprite, evt : MouseEvent) : Bool{
		// Search for an object to handle this drop and return true one is found.
		// Note: Search from front to back, so the front-most object catches the dropped object.
		if (app.isIn3D)             app.stagePane.visible = true;
		var possibleTargets : Array<Dynamic> = stage.getObjectsUnderPoint(new Point(evt.stageX / app.scaleX, evt.stageY / app.scaleY));
		if (app.isIn3D) {
			app.stagePane.visible = false;
			if (possibleTargets.length == 0 && app.stagePane.scrollRect.contains(app.stagePane.mouseX, app.stagePane.mouseY)) 
				possibleTargets.push(app.stagePane);
		}
		possibleTargets.reverse();
		var tried : Array<Dynamic> = [];
		for (o in possibleTargets){
			while (o){  // see if some parent can handle the drop  
				if (Lambda.indexOf(tried, o) == -1) {
					if (Compat.hasMethod(o, "handleDrop") && o.handleDrop(droppedObj))                         return true;
					tried.push(o);
				}
				o = o.parent;
			}
		}
		return false;
	}

	private function drop(evt : MouseEvent) : Void{
		if (carriedObj == null)             return;
		if (Std.is(carriedObj, DisplayObject))             carriedObj.cacheAsBitmap = false;
		carriedObj.stopDrag();
		removeDropShadowFrom(carriedObj);
		carriedObj.parent.removeChild(carriedObj);

		if (!dropHandled(carriedObj, evt)) {
			if (Std.is(carriedObj, Block)) {
				cast((carriedObj), Block).restoreOriginalState();
			}
			else if (originalParent != null) {  // put carriedObj back where it came from  
				carriedObj.x = originalPosition.x;
				carriedObj.y = originalPosition.y;
				carriedObj.scaleX = carriedObj.scaleY = originalScale;
				originalParent.addChild(carriedObj);
				if (Std.is(carriedObj, ScratchSprite)) {
					var ss : ScratchSprite = cast(carriedObj, ScratchSprite);
					ss.updateCostume();
					ss.updateBubble();
				}
			}
		}
		app.scriptsPane.draggingDone();
		carriedObj = null;
		originalParent = null;
		originalPosition = null;
	}

	private function addDropShadowTo(o : DisplayObject) : Void{
		var f : DropShadowFilter = new DropShadowFilter();
		var blockScale : Float = ((app.scriptsPane != null)) ? app.scriptsPane.scaleX : 1;
		f.distance = 8 * blockScale;
		f.blurX = f.blurY = 2;
		f.alpha = 0.4;
		o.filters = o.filters.concat([f]);
	}

	private function removeDropShadowFrom(o : DisplayObject) : Void{
		var newFilters : Array<openfl.filters.BitmapFilter> = [];
		for (f in o.filters){
			if (!(Std.is(f, DropShadowFilter)))                 newFilters.push(f);
		}
		o.filters = newFilters;
	}

	public function showBubble(text : String, x : Float, y : Float, width : Float = 0) : Void{
		hideBubble();
		bubble = new TalkBubble(text != null ? text : " ", "say", "result", this);
		bubbleStartX = stage.mouseX;
		bubbleStartY = stage.mouseY;
		var bx : Float = x + width;
		var by : Float = y - bubble.height;
		if (bx + bubble.width > stage.stageWidth - bubbleMargin && x - bubble.width > bubbleMargin) {
			bx = x - bubble.width;
			bubble.setDirection("right");
		}
		else {
			bubble.setDirection("left");
		}
		bubble.x = Math.max(bubbleMargin, Math.min(stage.stageWidth - bubbleMargin, bx));
		bubble.y = Math.max(bubbleMargin, Math.min(stage.stageHeight - bubbleMargin, by));

		var f : DropShadowFilter = new DropShadowFilter();
		f.distance = 4;
		f.blurX = f.blurY = 8;
		f.alpha = 0.2;
		bubble.filters = bubble.filters.concat([f]);

		stage.addChild(bubble);
	}

	public function hideBubble() : Void{
		if (bubble != null) {
			stage.removeChild(bubble);
			bubble = null;
		}
	}

	/* Debugging */

	private var debugSelection : DisplayObject;

	private function showDebugFeedback(evt : MouseEvent) : Void{
		// Highlights the clicked DisplayObject and prints it in the debug console.
		// Multiple clicks walk up the display hierarchy. This is useful for understanding
		// the structure of the UI.

		evt.stopImmediatePropagation();  // don't let the clicked object handle this event  
		gesture = "debug";  // prevent mouseMove and mouseUp processing  

		var stage : DisplayObject = evt.target.stage;
		if (debugSelection != null) {
			removeDebugGlow(debugSelection);
			if (debugSelection.getRect(stage).containsPoint(new Point(stage.mouseX, stage.mouseY))) {
				debugSelection = debugSelection.parent;
			}
			else {
				debugSelection = cast((evt.target), DisplayObject);
			}
		}
		else {
			debugSelection = cast((evt.target), DisplayObject);
		}
		if (Std.is(debugSelection, Stage)) {
			debugSelection = null;
			return;
		}
		trace(debugSelection);
		addDebugGlow(debugSelection);
	}

	private function addDebugGlow(o : DisplayObject) : Void{
		var newFilters : Array<openfl.filters.BitmapFilter> = [];
		if (o.filters != null)             newFilters = o.filters;
		var f : GlowFilter = new GlowFilter(0xFFFF00);
		f.strength = 15;
		f.blurX = f.blurY = 6;
		f.inner = true;
		newFilters.push(f);
		o.filters = newFilters;
	}

	private function removeDebugGlow(o : DisplayObject) : Void{
		var newFilters : Array<openfl.filters.BitmapFilter> = [];
		for (f in o.filters){
			if (!(Std.is(f, GlowFilter)))                 newFilters.push(f);
		}
		o.filters = newFilters;
	}
}
