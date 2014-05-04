package as3hx;
import as3hx.As3;
import as3hx.Tokenizer;
import as3hx.ParserUtils;
import as3hx.parsers.ObjectParser;
import as3hx.parsers.ExprParser;
import as3hx.parsers.FunctionParser;
import as3hx.parsers.CaseBlockParser;
import as3hx.parsers.XMLReader;
import as3hx.parsers.StructureParser;
import as3hx.parsers.TypeParser;
import as3hx.parsers.E4XParser;
import as3hx.parsers.ImportParser;
import as3hx.Error;

using as3hx.Debug;


/**
 * ...
 * @author Nicolas Cannasse
 * @author Russell Weir
 */
class Parser {


    public var tokenizer : Tokenizer;

    // implementation
    var path : String;
    var filename : String;
    var cfg : Config;
    var typesSeen : Array<Dynamic>;
    var typesDefd : Array<Dynamic>;
    var genTypes : Array<GenType>;

    public function new(config:Config) {
        this.cfg = config;
        this.typesSeen = new Array<Dynamic>();
        this.typesDefd = new Array<Dynamic>();
        this.genTypes = new Array<GenType>();
    }

    public function parseString( s : String, path : String, filename : String ) {
        //convert Windows newline to Unix ones
        s = StringTools.replace(s, '\r\n', '\n');
        this.path = path;
        this.filename = filename;
        return parse( new haxe.io.StringInput(s) );
    }

    public function parse( s : haxe.io.Input ) {
        tokenizer = new Tokenizer(s);
        return parseProgram();
    }

    public function parseInclude(p:String, call:Void->Void) {
        var oldInput = tokenizer.input;
        var oldLine = tokenizer.line;
        var oldPath = path;
        var oldFilename = filename;
        var file = path + "/" + p;
        var parts = file.split("/");
        filename = parts.pop();
        path = parts.join("/");
        Debug.openDebug("Parsing included file " + file + "\n", tokenizer.line);
        if (!sys.FileSystem.exists(file)) throw "Error: file '" + file + "' does not exist, at " + oldLine;
        var content = sys.io.File.getContent(file);
        tokenizer.line = 1;
        tokenizer.input = new haxe.io.StringInput(content);
        try {
            call();
        } catch(e:Dynamic) {
            throw "Error " + e + " while parsing included file " + file + " at " + oldLine;
        }
        tokenizer.input = oldInput;
        tokenizer.line = oldLine;
        path = oldPath;
        filename = oldFilename;
        Debug.closeDebug("Finished parsing file " + file, tokenizer.line);
    }
    
    function parseProgram() : Program {
        Debug.dbgln("parseProgram()", tokenizer.line);
        var pack = [];
        var header:Array<Expr> = [];

        // look for first 'package'
        var tk = tokenizer.token();
        var a = ParserUtils.explodeComment(tk);

        for(t in a) {
            switch(t) {
            case TId(s):
                if( s != "package" )
                    ParserUtils.unexpected(t);
                if( ParserUtils.opt(tokenizer.token, tokenizer.add, TBrOpen) )
                    pack = []
                else {
                    pack = parsePackageName();
                    tokenizer.ensure(TBrOpen);
                }
                
            case TCommented(s,b,t):
                if(t != null) throw "Assert error " + Tokenizer.tokenString(t);
                header.push(ECommented(s,b,false,null));
            case TNL(t):    
                header.push(ENL(null));
            default:
                ParserUtils.unexpected(t);
            }
        }
        
        

        // parse package
        var imports = [];
        var inits : Array<Expr> = [];
        var defs = [];
        var meta : Array<Expr> = [];
        var closed = false;
        var inNamespace = false;
        var inCondBlock = false;
        var outsidePackage = false;
        var hasOustidePackageMetaImport = false;

        var pf : Bool->Void = null;
        pf = function(included:Bool) {
        while( true ) {
            var tk = tokenizer.token();
            switch( tk ) {
            case TBrClose: // }
                if( inNamespace ) {
                    inNamespace = false;
                    continue;
                }
                else if( !closed ) {
                    closed = true;
                    outsidePackage = true;
                    continue;
                }
                else if (inCondBlock) {
                    inCondBlock = false;
                    continue;
                }
            case TBrOpen: // {
                if(inNamespace)
                    continue;
                // private classes outside of first package {}
                if( !closed ) {
                    ParserUtils.unexpected(tk);
                }
                closed = false;
                continue;
            case TEof:
                if( included )
                    return;
                if( closed )
                    break;
            case TBkOpen: // [
                tokenizer.add(tk);
                meta.push(parseMetadata());
                continue;
            case TId(id):
                switch( id ) {
                case "import":
                    var impt = ImportParser.parse(tokenizer, cfg);

                    //outsidePackage = false;
                    //note : when parsing package, user defined imports
                    //are stored as meta, this way, comments can be kept
                    if (impt.length > 0) {
                        if (!outsidePackage) {
                            meta.push(EImport(impt));
                        }
                        //coner case : import for AS3 private class, for those,
                        //need to add them to regular import list or to first
                        //class metadata so that they
                        //get written at the top of file, as in Haxe all imports
                        //must be at the top of the file
                        //
                        //note : this is very hackish
                        else {
                            //no class def available, put in general import list
                            if (defs.length == 0) {
                                imports.push(impt);
                            }

                            //else check if can add to first class meta
                            switch (defs[0]) {
                                case CDef(c):

                                    //also put the newline preceding the import
                                    //in the first class meta
                                    if (meta.length > 0) {
                                        switch(meta[meta.length-1]) {
                                            case ENL(e):
                                                if (e == null) {
                                                    c.meta.push(meta.pop());
                                                }
                                            default:
                                        }
                                    }

                                    //remove extra new line generated for before
                                    //class generation if not first moved import
                                    if (hasOustidePackageMetaImport) {
                                        c.meta.pop();
                                        c.meta.pop();
                                    }
                                    
                                    //put the import in the first class meta
                                    c.meta.push(EImport(impt));

                                    //add new line before class definition
                                    c.meta.push(ENL(null));
                                    c.meta.push(ENL(null));

                                    hasOustidePackageMetaImport = true;

                                //put in regular import list
                                default:    
                                    imports.push(impt);
                            }
                        }

                    }
                       
                    tokenizer.end();
                    continue;
                case "use":
                    parseUse();
                    continue;
                case "final", "public", "class", "internal", "interface", "dynamic", "function":
                    inNamespace = false;
                    tokenizer.add(tk);
                    var d = parseDefinition(meta);
                    switch(d) {
                        case CDef(c):
                            for(i in c.imports)
                                imports.push(i);
                            for(i in inits)
                                c.inits.push(i);
                            c.imports = [];
                            inits = [];
                        default:
                    }
                    defs.push(d);
                    meta = [];
                    continue;
                case "include":
                    tk = tokenizer.token();
                    switch(tk) {
                        case TConst(c):
                            switch(c) {
                                case CString(path):
                                    var oldClosed = closed;
                                    closed = false;
                                    parseInclude(path,pf.bind(true));
                                    tokenizer.end();
                                    closed = oldClosed;
                                default:
                                    ParserUtils.unexpected(tk);
                            }
                        default:
                            ParserUtils.unexpected(tk);
                    }
                    continue;
                default:

                    if(ParserUtils.opt(tokenizer.token, tokenizer.add, TNs)) {
                        var ns : String = id;
                        var t = ParserUtils.uncomment(tokenizer.token());

                        switch(t) {
                            case TId(id2):
                                id = id2;
                            default:
                                ParserUtils.unexpected(t);
                        }

                        if (Lambda.has(cfg.conditionalVars, ns + "::" + id)) {
                            // this is a user supplied conditional compilation variable
                            Debug.openDebug("conditional compilation: " + ns + "::" + id, tokenizer.line);
                           // condVars.push(ns + "_" + id);
                            meta.push(ECondComp(ns + "_" + id, null, null));
                            inCondBlock = true;
                            t = tokenizer.token();
                            switch (t) {
                                case TBrOpen:
                                    pf(false);
                                default:
                                    tokenizer.add(t);
                                    pf(false);
                            }
                           // condVars.pop();
                            Debug.closeDebug("end conditional compilation: " + ns + "::" + id, tokenizer.line);
                            continue;
                        } else {
                            ParserUtils.unexpected(t);
                        }
                    }
                    else if(ParserUtils.opt(tokenizer.token, tokenizer.add, TSemicolon)) {
                        // class names without an import statement used
                        // for forcing compilation and linking.
                        inits.push(EIdent(id));
                        continue;
                    } else {
                        ParserUtils.unexpected(tk);
                    }
                }
            case TSemicolon:
                continue;
            case TNL(t):
                meta.push(ENL(null));
                tokenizer.add(t);
                continue;   
            case TCommented(s,b,t):
                var t = ParserUtils.uncomment(tk);
                switch(t) {
                case TBkOpen:
                    tokenizer.add(t);
                    meta.push(ParserUtils.makeECommented(tk, parseMetadata()));
                    continue;
                default:
                    tokenizer.add(t);
                    meta.push(ParserUtils.makeECommented(tk, null));
                }
                continue;
            default:
            }
            ParserUtils.unexpected(tk);
        }
        };
        pf(false);
        if( !closed )
            ParserUtils.unexpected(TEof);

        return {
            header : header,
            pack : pack,
            imports : imports,
            typesSeen : typesSeen,
            typesDefd : typesDefd,
            genTypes : genTypes,
            defs : defs,
            footer : meta
        };
    }
    
    function parseUse() {
        tokenizer.ensure(TId("namespace"));
        var ns = tokenizer.id();
        tokenizer.end();
    }

    function parseMetadata() : Expr {
        Debug.dbg("parseMetadata()", tokenizer.line);
        tokenizer.ensure(TBkOpen);
        var name = tokenizer.id();
        var args = [];
        if( ParserUtils.opt(tokenizer.token, tokenizer.add, TPOpen) )
            while( !ParserUtils.opt(tokenizer.token, tokenizer.add, TPClose) ) {
                var n = null;
                switch(tokenizer.peek()) {
                case TId(i):
                    n = tokenizer.id();
                    if(!ParserUtils.opt(tokenizer.token, tokenizer.add, TOp("="))) {
                        args.push( { name : null, val : EIdent(n) } );
                        ParserUtils.opt(tokenizer.token, tokenizer.add, TComma);
                        continue;
                    }
                case TConst(_):
                    null;
                default:
                    ParserUtils.unexpected(tokenizer.peek());
                }
                var e = ExprParser.parse(tokenizer, typesSeen, cfg, false);
                args.push( { name : n, val :e } );
                ParserUtils.opt(tokenizer.token, tokenizer.add, TComma);
            }
        tokenizer.ensure(TBkClose);
        Debug.dbgln(" -> " + { name : name, args : args }, tokenizer.line);
        return EMeta({ name : name, args : args });
    }
    
    function parseDefinition(meta:Array<Expr>) : Definition {
        Debug.dbgln("parseDefinition()" + meta, tokenizer.line);
        var kwds = [];
        while( true ) {
            var id = tokenizer.id();
            switch( id ) {
            case "public", "internal", "final", "dynamic": kwds.push(id);
            case "use":
                parseUse();
                continue;
            case "class":
                var c = parseClass(kwds,meta,false);
                typesDefd.push(c);
                return CDef(c);
            case "interface":
                var c = parseClass(kwds,meta,true);
                typesDefd.push(c);
                return CDef(c);
            case "function":
                return FDef(parseFunDef(kwds, meta));
            case "namespace":
                return NDef(parseNsDef(kwds, meta));
            default: ParserUtils.unexpected(TId(id));
            }
        }
        return null;
    }
    
    function parseFunDef(kwds, meta) : FunctionDef {
        Debug.dbgln("parseFunDef()", tokenizer.line);
        var fname = tokenizer.id();
        var f = FunctionParser.parse(tokenizer, typesSeen, cfg);
        return {
            kwds : kwds,
            meta : meta,
            name : fname,
            f : f
        };
    }
    
    function parseNsDef(kwds, meta) : NamespaceDef {
        Debug.dbgln("parseNsDef()", tokenizer.line);
        var name = tokenizer.id();
        var value = null;
        if( ParserUtils.opt(tokenizer.token, tokenizer.add, TOp("=")) ) {
            var t = tokenizer.token();
            value = switch( t ) {
            case TConst(c):
                switch( c ) {
                case CString(str): str;
                default: ParserUtils.unexpected(t);
                }
            default:
                ParserUtils.unexpected(t);
            };
        }
        return {
            kwds : kwds,
            meta : meta,
            name : name,
            value : value
        };
    }
    
    function parseClass(kwds,meta:Array<Expr>,isInterface:Bool) : ClassDef {
        var cname = tokenizer.id();
        var classMeta = meta;
        var imports = [];
        meta = [];
        Debug.openDebug("parseClass("+cname+")", tokenizer.line, true);
        var fields = new Array();
        var impl = [], extend = null, inits = [];
        var condVars:Array<String> = [];
        while( true ) {
            if( ParserUtils.opt(tokenizer.token, tokenizer.add, TId("implements")) ) {
                impl.push(TypeParser.parse(tokenizer, typesSeen, cfg));
                while( ParserUtils.opt(tokenizer.token, tokenizer.add, TComma) )
                    impl.push(TypeParser.parse(tokenizer, typesSeen, cfg));
                continue;
            }
            if( ParserUtils.opt(tokenizer.token, tokenizer.add, TId("extends")) ) {
                if(!isInterface) {
                    extend = TypeParser.parse(tokenizer, typesSeen, cfg);
                    if(cfg.testCase) {
                        switch(extend) {
                            case TPath(a):
                                var ex = a.join(".");
                                if(ex == "Sprite" || ex == "flash.display.Sprite")
                                    extend = null;
                            default:
                        }
                    }
                }
                else {
                    impl.push(TypeParser.parse(tokenizer, typesSeen, cfg));
                    while( ParserUtils.opt(tokenizer.token, tokenizer.add, TComma) )
                        impl.push(TypeParser.parse(tokenizer, typesSeen, cfg));
                }
                continue;
            }
            break;
        }
        tokenizer.ensure(TBrOpen);

        var pf : Bool->Bool->Void = null;

        pf = function(included:Bool,inCondBlock:Bool) {
        while( true ) {
            // check for end of class
            if( ParserUtils.opt2(tokenizer.token, tokenizer.add, TBrClose, meta) ) break;
            var kwds = [];
            // parse all comments and metadata before next field
            while( true ) {
                var tk = tokenizer.token();
                switch( tk ) {
                case TSemicolon:
                    continue;
                case TBkOpen:
                    tokenizer.add(tk);
                    meta.push(parseMetadata());
                    continue;
                case TCommented(s,b,t):
                    tokenizer.add(t);
                    meta.push(ECommented(s,b,false,null));
                case TNL(t):
                    tokenizer.add(t);
                    meta.push(ENL(null));
                case TEof:
                    if(included)
                        return;
                    tokenizer.add(tk);
                    break;
                default:
                    tokenizer.add(tk);
                    break;
                }
            }

            while( true )  {
                var t = tokenizer.token();
                switch( t ) {
                case TId(id):
                    switch( id ) {
                    case "public", "static", "private", "protected", "override", "internal", "final": kwds.push(id);
                    case "const":
                        kwds.push(id);
                        do {
                            fields.push(parseClassVar(kwds, meta, condVars.copy()));
                            meta = [];
                        } while( ParserUtils.opt(tokenizer.token, tokenizer.add, TComma) );
                        tokenizer.end();
                        if (condVars.length != 0 && !inCondBlock) {
                            return;
                        }
                        break;
                    case "var":
                        do {
                            fields.push(parseClassVar(kwds, meta, condVars.copy()));
                            meta = [];
                        } while( ParserUtils.opt(tokenizer.token, tokenizer.add, TComma) );
                        tokenizer.end();
                        if (condVars.length != 0 && !inCondBlock) {
                            return;
                        }
                        break;
                    case "function":
                        fields.push(parseClassFun(kwds, meta, condVars.copy(), isInterface));
                        meta = [];
                        if (condVars.length != 0 && !inCondBlock) {
                            return;
                        }
                        break;
                    case "import":
                        var impt = ImportParser.parse(tokenizer, cfg);
                        if (impt.length > 0) imports.push(impt);
                        tokenizer.end();
                        break;
                    case "use":
                        parseUse();
                        break;
                    case "include":
                        t = tokenizer.token();
                        switch(t) {
                            case TConst(c):
                                switch(c) {
                                    case CString(path):
                                        parseInclude(path,pf.bind(true, false));
                                        tokenizer.end();
                                    default:
                                        ParserUtils.unexpected(t);
                                }
                            default:
                                ParserUtils.unexpected(t);
                        }
                    default:
                        kwds.push(id);
                    }
                case TCommented(s,b,t):
                    tokenizer.add(t);
                    meta.push(ECommented(s,b,false,null));
                case TEof:
                    if(included)
                        return;
                    tokenizer.add(t);
                    while( kwds.length > 0 )
                        tokenizer.add(TId(kwds.pop()));
                    inits.push(ExprParser.parse(tokenizer, typesSeen, cfg, false));
                    tokenizer.end();
                case TNs:
                    if (kwds.length != 1) {
                        ParserUtils.unexpected(t);
                    }
                    var ns = kwds.pop();
                    t = tokenizer.token();
                    switch(t) {
                        case TId(id):
                            if (Lambda.has(cfg.conditionalVars, ns + "::" + id)) {
                                // this is a user supplied conditional compilation variable
                                Debug.openDebug("conditional compilation: " + ns + "::" + id, tokenizer.line);
                                condVars.push(ns + "_" + id);
                                meta.push(ECondComp(ns + "_" + id, null, null));
                                t = tokenizer.token();

                                var f:Token->Void = null;
                                f = function(t) {
                                    switch (t) {
                                        case TBrOpen:
                                            pf(false, true);

                                        case TCommented(s,b,t):
                                            f(t);   

                                        case TNL(t):
                                            meta.push(ENL(null));
                                            f(t);    

                                        default:
                                            tokenizer.add(t);
                                            pf(false, false);
                                        } 
                                }
                                f(t);
                              
                                condVars.pop();
                                Debug.closeDebug("end conditional compilation: " + ns + "::" + id, tokenizer.line);
                                break;
                            } else {
                                ParserUtils.unexpected(t);
                            }
                        default:
                            ParserUtils.unexpected(t);
                    }
                case TNL(t):
                    tokenizer.add(t);
                    meta.push(ENL(null));

                default:
                    Debug.dbgln("init block: " + t, tokenizer.line);
                    tokenizer.add(t);
                    while( kwds.length > 0 )
                        tokenizer.add(TId(kwds.pop()));
                    inits.push(ExprParser.parse(tokenizer, typesSeen, cfg, false));
                    tokenizer.end();
                    break;
                }
            }
        }
        };
        pf(false, false);

        //trace("*** " + meta);
        for(m in meta) {
            switch(m) {
            case ECommented(s,b,t,e):
                if(ParserUtils.uncommentExpr(m) != null)
                    throw "Assert error: " + m;
                var a = ParserUtils.explodeCommentExpr(m);
                for(i in a) {
                    switch(i) {
                        case ECommented(s,b,t,e):
                            fields.push({name:null, meta:[ECommented(s,b,false,null)], kwds:[], kind:FComment, condVars:[]});
                        default:
                            throw "Assert error: " + i;
                    }
                }
            default:
                throw "Assert error: " + m;
            }
        }
        Debug.closeDebug("parseClass("+cname+") finished", tokenizer.line);
        return {
            meta : classMeta,
            kwds : kwds,
            imports : imports,
            isInterface : isInterface,
            name : cname,
            fields : fields,
            implement : impl,
            extend : extend,
            inits : inits
        };
    }

    function parseClassVar(kwds,meta,condVars:Array<String>) : ClassField {
        Debug.openDebug("parseClassVar(", tokenizer.line);
        var name = tokenizer.id();
        Debug.dbgln(name + ")", tokenizer.line, false);
        var t = null, val = null;
        if( ParserUtils.opt(tokenizer.token, tokenizer.add, TColon) )
            t = TypeParser.parse(tokenizer, typesSeen, cfg);
        if( ParserUtils.opt(tokenizer.token, tokenizer.add, TOp("=")) )
            val = ExprParser.parse(tokenizer, typesSeen, cfg, false);

        var rv = {
            meta : meta,
            kwds : kwds,
            name : StringTools.replace(name, "$", "__DOLLAR__"),
            kind : FVar(t, val),
            condVars : condVars
        };
        
        var genType = ParserUtils.generateTypeIfNeeded(rv);
        if (genType != null)
            this.genTypes.push(genType);

        Debug.closeDebug("parseClassVar -> " + rv, tokenizer.line);
        return rv;
    }

    function parseClassFun(kwds:Array<String>,meta,condVars:Array<String>, isInterface:Bool) : ClassField {
        Debug.openDebug("parseClassFun(", tokenizer.line);
        var name = tokenizer.id();
        if( name == "get" || name == "set" ) {
            switch (tokenizer.peek()) {
                case TPOpen:
                    // not a property
                    null;
                default:
                    // a property, so better have an id next
                    kwds.push(name);
                    name = tokenizer.id();
            }
        }
        Debug.dbgln(Std.string(kwds) + " " + name + ")", tokenizer.line, false);
        var f = FunctionParser.parse(tokenizer, typesSeen, cfg, isInterface);
        tokenizer.end();
        Debug.closeDebug("end parseClassFun()", tokenizer.line);
        return {
            meta : meta,
            kwds : kwds,
            name : StringTools.replace(name, "$", "__DOLLAR__"),
            kind : FFun(f),
            condVars : condVars
        };
    }
    
    function parsePackageName() {
        Debug.dbg("parsePackageName()", tokenizer.line);
        var a = [tokenizer.id()];
        while( true ) {
            var tk = tokenizer.token();
            switch( tk ) {
            case TDot:
                tk = tokenizer.token();
                switch(tk) {
                case TId(id): a.push(id);
                default: ParserUtils.unexpected(tk);
                }
            default:
                tokenizer.add(tk);
                break;
            }
        }
        Debug.dbgln(" -> " + a, tokenizer.line);
        return a;
    }
}
