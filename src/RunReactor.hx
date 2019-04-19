package;

import as3hx.Writer;
import hx.concurrent.executor.Executor;
import hx.files.*;
import hx.files.watcher.*;

using haxe.io.Path;

class RunReactor 
{
	public static function main() {
		new RunReactor();
	}
	
	public function new() 
	{
		var args = Sys.args().copy();
		if (args.length != 2) {
			Sys.stderr().writeString("run-reactor.n src dst");
			return;
		}
		var src = (Sys.getCwd() + args[0]).normalize();
		var dst = (Sys.getCwd() + args[1]).normalize();
		
		Sys.stdout().writeString('from ${src}\n');
		Sys.stdout().writeString('to ${dst}\n');
		
		var cfg = new as3hx.Config();
		
		var ex = Executor.create(); // executor is used to schedule scanning tasks and
        var fw = new PollingFileWatcher(ex, 100 /*polling interval in MS*/);
		
		fw.watch(src);
		fw.subscribe(function (event) {
            switch(event) {
                case DIR_CREATED(dir):       trace('Dir created: $dir');
                case DIR_DELETED(dir):       trace('Dir deleted: $dir');
                case DIR_MODIFIED(dir, _):   trace('Dir modified: $dir');
                case FILE_CREATED(file):     processFile(cfg, src, dst, file);
				case FILE_MODIFIED(file, _): processFile(cfg, src, dst, file);
                case FILE_DELETED(file): processFile(cfg, src, dst, file);
            }
        });
		
		Sys.stdin().readLine();
		
		fw.stop();
        ex.stop();
	}
	
	static function processFile(cfg: as3hx.Config, srcDir: String, dstDir: String, file: File): Void {
		var filePath = file.path.toString().normalize();
		if (!filePath.endsWith(".as")) {
			return;
		}
		if (Run.isExcludeFile(cfg.excludePaths, filePath)) {
			return;
		}
		if (filePath.indexOf(srcDir) != 0) {
			Sys.stderr().writeString('WARN: $filePath not from $srcDir');
			return;
		}
		var releativeFile = filePath.substr(srcDir.length);
		var dstFile = File.of((dstDir.addTrailingSlash() + releativeFile).normalize());
		
		if (dstFile.path.exists()) {
			dstFile.delete();
		}
		if (file.path.exists()) {
			var writer = new Writer(cfg);
			Run.processFile(cfg, writer, srcDir, dstDir, releativeFile);
		}
	}
}