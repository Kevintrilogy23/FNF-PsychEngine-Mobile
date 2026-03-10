package;

import debug.FPSCounter;

import flixel.graphics.FlxGraphic;
import flixel.FlxGame;
import flixel.FlxState;
import haxe.io.Path;
import openfl.Assets;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.display.StageScaleMode;
import lime.app.Application;
import states.TitleState;

#if HSCRIPT_ALLOWED
import crowplexus.iris.Iris;
import psychlua.HScript.HScriptInfos;
#end

#if (linux || mac)
import lime.graphics.Image;
#end

#if desktop
import backend.ALSoftConfig;
#end

#if CRASH_HANDLER
import openfl.events.UncaughtErrorEvent;
import haxe.CallStack;
import haxe.io.Path;
#end

import backend.Highscore;

#if (linux && !debug)
@:cppInclude('./external/gamemode_client.h')
@:cppFileCode('#define GAMEMODE_AUTO')
#end

class Main extends Sprite
{
	public static final game = {
		width: 1280,
		height: 720,
		initialState: TitleState,
		framerate: 60,
		skipSplash: true,
		startFullscreen: false
	};

	public static var fpsVar:FPSCounter;

	public static function main():Void
	{
		Lib.current.addChild(new Main());
	}

	public function new()
	{
		super();

		#if (cpp && windows)
		backend.Native.fixScaling();
		#end

		#if android
		Sys.setCwd(Path.addTrailingSlash(getExternalStorageDir()));
		#elseif ios
		Sys.setCwd(lime.system.System.applicationStorageDirectory);
		#end

		#if VIDEOS_ALLOWED
		hxvlc.util.Handle.init(#if (hxvlc >= "1.8.0") ['--no-lua'] #end);
		#end

		#if LUA_ALLOWED
		Mods.pushGlobalMods();
		#end
		Mods.loadTopMod();

		FlxG.save.bind('funkin', CoolUtil.getSavePath());
		Highscore.load();

		#if HSCRIPT_ALLOWED
		Iris.warn = function(x, ?pos:haxe.PosInfos) {
			Iris.logLevel(WARN, x, pos);
			var newPos:HScriptInfos = cast pos;
			if (newPos.showLine == null) newPos.showLine = true;
			var msgInfo:String = (newPos.funcName != null ? '(${newPos.funcName}) - ' : '') + '${newPos.fileName}:';
			#if LUA_ALLOWED
			if (newPos.isLua == true) {
				msgInfo += 'HScript:';
				newPos.showLine = false;
			}
			#end
			if (newPos.showLine == true) msgInfo += '${newPos.lineNumber}:';
			msgInfo += ' $x';
			if (PlayState.instance != null)
				PlayState.instance.addTextToDebug('WARNING: $msgInfo', FlxColor.YELLOW);
		}
		Iris.error = function(x, ?pos:haxe.PosInfos) {
			Iris.logLevel(ERROR, x, pos);
			var newPos:HScriptInfos = cast pos;
			if (newPos.showLine == null) newPos.showLine = true;
			var msgInfo:String = (newPos.funcName != null ? '(${newPos.funcName}) - ' : '') + '${newPos.fileName}:';
			#if LUA_ALLOWED
			if (newPos.isLua == true) {
				msgInfo += 'HScript:';
				newPos.showLine = false;
			}
			#end
			if (newPos.showLine == true) msgInfo += '${newPos.lineNumber}:';
			msgInfo += ' $x';
			if (PlayState.instance != null)
				PlayState.instance.addTextToDebug('ERROR: $msgInfo', FlxColor.RED);
		}
		Iris.fatal = function(x, ?pos:haxe.PosInfos) {
			Iris.logLevel(FATAL, x, pos);
			var newPos:HScriptInfos = cast pos;
			if (newPos.showLine == null) newPos.showLine = true;
			var msgInfo:String = (newPos.funcName != null ? '(${newPos.funcName}) - ' : '') + '${newPos.fileName}:';
			#if LUA_ALLOWED
			if (newPos.isLua == true) {
				msgInfo += 'HScript:';
				newPos.showLine = false;
			}
			#end
			if (newPos.showLine == true) msgInfo += '${newPos.lineNumber}:';
			msgInfo += ' $x';
			if (PlayState.instance != null)
				PlayState.instance.addTextToDebug('FATAL: $msgInfo', 0xFFBB0000);
		}
		#end

		#if LUA_ALLOWED Lua.set_callbacks_function(cpp.Callable.fromStaticFunction(psychlua.CallbackHandler.call)); #end
		Controls.instance = new Controls();
		ClientPrefs.loadDefaultKeys();
		#if ACHIEVEMENTS_ALLOWED Achievements.load(); #end
		addChild(new FlxGame(game.width, game.height, game.initialState, game.framerate, game.framerate, game.skipSplash, game.startFullscreen));

		#if !mobile
		fpsVar = new FPSCounter(10, 3, 0xFFFFFF);
		addChild(fpsVar);
		Lib.current.stage.align = "tl";
		Lib.current.stage.scaleMode = StageScaleMode.NO_SCALE;
		if (fpsVar != null)
			fpsVar.visible = ClientPrefs.data.showFPS;
		#end

		#if (linux || mac)
		var icon = Image.fromFile("icon.png");
		Lib.current.stage.window.setIcon(icon);
		#end

		#if html5
		FlxG.autoPause = false;
		FlxG.mouse.visible = false;
		#end

		#if mobile
		FlxG.autoPause = false;
		#end

		FlxG.fixedTimestep = false;
		FlxG.game.focusLostFramerate = 60;

		#if !mobile
		FlxG.keys.preventDefaultKeys = [TAB];
		#end

		#if CRASH_HANDLER
		Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onCrash);
		#end

		#if DISCORD_ALLOWED
		DiscordClient.prepare();
		#end

		FlxG.signals.gameResized.add(function (w, h) {
			if (FlxG.cameras != null) {
				for (cam in FlxG.cameras.list) {
					if (cam != null && cam.filters != null)
						resetSpriteCache(cam.flashSprite);
				}
			}
			if (FlxG.game != null)
				resetSpriteCache(FlxG.game);
		});
	}

	/**
	 * Retorna o diretório de storage externo do Android via JNI.
	 * Equivalente a Context.getExternalFilesDir(null).getAbsolutePath()
	 * Resultado: /storage/emulated/0/Android/data/com.shadowmario.psychengine/files
	 *
	 * Fallback: internal storage via lime, caso o JNI falhe.
	 */
	#if android
	public static function getExternalStorageDir():String
	{
		try
		{
			// Pega a instância da Activity principal do Lime
			var getInstance = lime.system.JNI.createStaticMethod(
				"org/haxe/lime/GameActivity",
				"getInstance",
				"()Lorg/haxe/lime/GameActivity;"
			);
			var activity = getInstance();

			// Chama getExternalFilesDir(null) — retorna um java.io.File
			var getExternalFilesDir = lime.system.JNI.createMemberMethod(
				"android/app/Activity",
				"getExternalFilesDir",
				"(Ljava/lang/String;)Ljava/io/File;"
			);
			var file = getExternalFilesDir(activity, null);

			// Converte File em String com getAbsolutePath()
			var getAbsolutePath = lime.system.JNI.createMemberMethod(
				"java/io/File",
				"getAbsolutePath",
				"()Ljava/lang/String;"
			);
			var path:String = getAbsolutePath(file);

			if (path != null && path.length > 0)
				return path;
		}
		catch (e:Dynamic)
		{
			trace('[WARN] getExternalStorageDir JNI failed: $e — falling back to internal storage');
		}

		// Fallback: internal storage
		return lime.system.System.applicationStorageDirectory;
	}
	#end

	static function resetSpriteCache(sprite:Sprite):Void {
		@:privateAccess {
			sprite.__cacheBitmap = null;
			sprite.__cacheBitmapData = null;
		}
	}

	#if CRASH_HANDLER
	function onCrash(e:UncaughtErrorEvent):Void
	{
		var errMsg:String = "";
		var path:String;
		var callStack:Array<StackItem> = CallStack.exceptionStack(true);
		var dateNow:String = Date.now().toString();

		dateNow = dateNow.replace(" ", "_");
		dateNow = dateNow.replace(":", "'");

		#if android
		var crashDir:String = Path.addTrailingSlash(getExternalStorageDir()) + "crash/";
		#elseif mobile
		var crashDir:String = lime.system.System.applicationStorageDirectory + "crash/";
		#else
		var crashDir:String = "./crash/";
		#end
		path = crashDir + "PsychEngine_" + dateNow + ".txt";

		for (stackItem in callStack)
		{
			switch (stackItem)
			{
				case FilePos(s, file, line, column):
					errMsg += file + " (line " + line + ")\n";
				default:
					Sys.println(stackItem);
			}
		}

		errMsg += "\nUncaught Error: " + e.error;
		#if officialBuild
		errMsg += "\nPlease report this error to the GitHub page: https://github.com/ShadowMario/FNF-PsychEngine";
		#end
		errMsg += "\n\n> Crash Handler written by: sqirra-rng";

		if (!FileSystem.exists(crashDir))
			FileSystem.createDirectory(crashDir);

		File.saveContent(path, errMsg + "\n");

		Sys.println(errMsg);
		Sys.println("Crash dump saved in " + Path.normalize(path));

		Application.current.window.alert(errMsg, "Error!");
		#if DISCORD_ALLOWED
		DiscordClient.shutdown();
		#end
		Sys.exit(1);
	}
	#end
}