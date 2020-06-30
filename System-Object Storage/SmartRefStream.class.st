"
Ordinary ReferenceStreams assume that the names and order of instance variables is exactly the same when an object file is written and read.  
	SmartRefStream allows object files to be read even after instance variables have changed or the entire class has been renamed.

When an object file is written, no one knows how the classes will change in the future.  Therefore, all conversion must be done when the file is read.  The key is to store enough information in the file about the names of the instance variables of all outgoing classes.  

SmartRefStream works best with only one tree of objects per file.  You can nextPut: more than once, but each object tree gets its own class structure description, which is big.  

Conversion of old objects is done by a method in each class called (convertToCurrentVersion: varDict refStream: smartRefStrm).  At fileOut time, ChangeSet>>checkForConversionMethods creates a prototype of this method (if Preference #conversionMethodsAtFileOut is true).  The programmer must edit this method to 
    (1) test if the incoming object needs conversion, 
    (2) put non-nil values into any new inst vars that need them, and 
    (3) save the data of any inst vars that are being deleted. 

Determining which old version is represented by the incoming object can be done in several ways: 
- noticing that a current inst var is nil when it should have data, 
- noticing that there is an older inst var name in the variable dictionary (varDict), 
- checking kinds of objects in one or more inst vars, or 
- retrieving the classVersion of the incoming object from the ref stream.  

If a class is renamed, a method goes into SmartRefStream telling the new name.  

The conversion method of the new class must be prepared to accept instances of the old class also.  If no inst var names have changed, the conversion method does nothing.




An example:  
    Suppose we change the representation of class Rectangle from ('origin' 'corner') to ('origin' 'extent').  Suppose lots of Rectangle instances are already out on files (in .pr project files, especially).  

    The programmer changes the class definition, modifies all the methods, and filesOut.  A series of dialogs appear, asking if instances Rectangle might be in an object file, if 'extent' needs to be non-nil (yes), and if the info in 'corner' needs to be preserved (yes).  This method appears:

Rectangle >> convertToCurrentVersion: varDict refStream: smartRefStrm
	""These variables are automatically stored into the new instance: #('origin').
	Test for this particular conversion.  Get values using expressions like (varDict at: 'foo').""

	""New variables: #('extent').  If a non-nil value is needed, please assign it.""
	""These are going away #('corner').  Possibly store their info in some other variable?""
	""Move your code above the ^ super...  Delete extra comments.""
	^ super convertToCurrentVersion: varDict refStream: smartRefStrm

The programmer modifies it to be:

Rectangle >> convertToCurrentVersion: varDict refStream: smartRefStrm

(varDict includesKey: 'extent') ifFalse: [""old version!""
	""Create the new extent, and preserve the info from the old corner""
	extent := (varDict at: 'corner') - origin.
	].
^ super convertToCurrentVersion: varDict refStream: smartRefStrm

	This conversion method stays in the system and is ready to convert the old format of Rectangle whenever one is encountered in an object file.  Note that the subclasses of Rectangle, (B3DViewport, CharacterBlock, and Quadrangle) do not need conversion methods.  Their instances will be converted by the code in Rectangle.  


	Files written by SmartRefStream are in standard fileout format.  You can mix raw objects with code to be filed in.  The file starts out in the normal fileOut format.  Definitions of new classes on the front.

structures 	Dictionary of (#Rectangle -> #(<classVersionInteger> 'origin' 'corner')).  Inst 
				var names are strings.
steady 		Set of Classes who have the same structure now as on the incoming file.
				Includes classes with same inst vars except for new ones added on the end.
reshaped 	Dictionary of Classes who have a different structure now from the incoming file.  
				Includes those with same inst vars but new version number.
				(old class name -> method selector to fill in data for version to version)
renamed	Dictionary of Classes who have a different name.  Make an instance of the new
			class, and send it the conversion call.
				(old class name symbol -> new class name).  
renamedConv	Dictionary of conversion selector for Classes who have a different name.
				(old class name symbol -> conversion selector).  
topCall		Tells if next or nextPut: are working on the top object in the tree.  
			nil if outside, the top object if deep inside.

See DataStream.typeIDFor: for where the tangle of objects is clipped, so the whole system will not be written on the file.

No object that is written on the file is ever a class.  All class definitions are filed in.  A class may be stored inside an ImageSegment that itself is stored in a SmartRefStream.




UniClasses are classes for the instance specific behavior of just one instance.  Subclasses of Player are an example.  When a UniClass is read in, and a class of the same name already exists, the incoming one is renamed.  ObjectScanner converts the filed-in code.

Values in instance variables of UniClasses are stored in the array that tells the class structure.  It is the fourth of the four top level objects.  #(version (class-structure) the-object ((#Player25 scripts slotInfo costumeDictionary) (#Player26 scripts slotInfo costumeDictionary))).

There is a separate subclass for doing veryDeepCopy (in memory).  Currently, any object for which objectToStoreOnDataStream return an object other than self, does this:  The new object (a DiskProxy) is traced.  When it comes time to go through the fields of the old object, they are not found as keys in references (DiskProxies are there instead).  So the old field value is left in the new object.  That is OK for StrikeFont, Class, MetaClass, DisplayScreen.  But the DiskProxies are evaluated, which takes a lot of time.

Some metaclasses are put into the structures table.  This is for when a block has a receiver that is a class.  See checkFatalReshape:.

ImageSegments:
	A ReferenceStream is used to enumerate objects to put inside an ImageSegment.  If an instance of a UniClass is seen, the class is put in also.
	A SmartRefStream is used to store the ImageSegment.  Roots are nil, and the segment is a wordArray.  We are encoding the outPointers.  Structures contains all classes from both places.  Must filter out UniClasses for some things, and do include them for putting source code at end of file.  Do not write any class inst vars in file.


--Ted Kaehler and Bob Arning.



How are the selectors in the '*Morphic-conversion' protocol ending with something like

         ttfclpomsswfpp0

constructed and what does it mean?


Answer:
It is the initials of all instance variables followed by the class version integer. The initials allow to detect  most changes to the instance variables, but if this is not sufficient (perhaps because the new var had the same initial, or the vars did not change in name at all) we still have the class version.

Most classes are still at version 0, but if you check implementers of classVersion you can find a few that were incremented to force a conversion on load.
"
Class {
	#name : #SmartRefStream,
	#superclass : #ReferenceStream,
	#instVars : [
		'structures',
		'steady',
		'reshaped',
		'renamed',
		'renamedConv',
		'superclasses',
		'progressBar',
		'objCount',
		'classInstVars'
	],
	#classVars : [
		'ScannedObject'
	],
	#category : #'System-Object Storage'
}

{ #category : #'initialize-release' }
SmartRefStream class >> cleanUpCategories [
	| list valid removed |
	"Look for all conversion methods that can't be used any longer.  Delete them."
	" SmartRefStream cleanUpCategories "

	"Two part selectors that begin with convert and end with a digit."
	"convertasossfe0: varDict asossfeu0: smartRefStrm"
	list := Symbol selectorsContaining: 'convert'.
	list := list select: [:symb | (symb beginsWith: 'convert') & (symb allButLast last isDigit)
				ifTrue: [(symb numArgs = 2)]
				ifFalse: [false]].
	valid := 0.  removed := 0.
	list do: [:symb |
		(self systemNavigation allClassesImplementing: symb) do: [:newClass | | newList newVers |
			newList := (Array with: newClass classVersion), (newClass allInstVarNames).
			newVers := self new versionSymbol: newList.
			(symb endsWith: (':',newVers,':')) 
				ifFalse: [
					"method is useless because can't convert to current shape"
					newClass removeSelector: symb.	"get rid of it"
					removed := removed + 1]
				ifTrue: [valid := valid + 1]]].
	Transcript cr; show: 'Removed: '; print: removed; 
		show: '		Kept: '; print: valid; show: ' '.
]

{ #category : #'browsing support' }
SmartRefStream class >> isConversionSelector: aLiteral [
	"Let mapClass: be found as sender of our conversion methods"
	^aLiteral isSymbol
	 and: [aLiteral last isDigit
	 and: [self includesSelector: aLiteral]]
]

{ #category : #'i/o' }
SmartRefStream class >> objectFromStreamedRepresentation: someBytes [

	| file |

	file := RWBinaryOrTextStream with: someBytes.
	file reset.
	^file fileInObjectAndCode
]

{ #category : #'i/o' }
SmartRefStream class >> read: aByteStream withClasses: structureArray [
	"Read an object off the stream, but first check structureArray against the current system."

	| me |
	me := self on: aByteStream.
	me noHeader.
	me structures: (structureArray at: 2).
	me superclasses: (structureArray at: 4).
	(me verifyStructure = 'conversion method needed') ifTrue: [^ nil].
	^ super next

]

{ #category : #'i/o' }
SmartRefStream class >> scanFrom: aByteStream [
	"During a code fileIn, we need to read in an object, and stash it in ScannedObject.  "

	| me |
	me := self on: aByteStream.
	ScannedObject := me next.
	aByteStream ascii.
	aByteStream next == $! ifFalse: [
		aByteStream close.
		self error: 'Object did not end correctly']. 
	"caller will close the byteStream"
	"HandMorph.readMorphFile will retrieve the ScannedObject"
]

{ #category : #'i/o' }
SmartRefStream class >> scanFrom: aByteStream environment: anEnvironment [
	^ self scanFrom: aByteStream
]

{ #category : #accessing }
SmartRefStream class >> scannedObject [
	"The most recently read in object.  Watch out for read-in that is interrupted and resumed.  May want to make this a dictionary?  "

	^ ScannedObject
]

{ #category : #accessing }
SmartRefStream class >> scannedObject: objOrNil [
	"Used to free up the last object stashed here.  "

	ScannedObject := objOrNil
]

{ #category : #accessing }
SmartRefStream class >> subObjects: anObject ofClass: aClass [
	"Return a collection of all instances of aClass that would be written out with anObject.  Does not actually write on the disk.  Inspect the result and ask for 'references to this object'."

	| dummy coll |
	dummy := ReferenceStream on: (DummyStream on: nil).
		"Write to a fake Stream, not a file"
	"Collect all objects"
	dummy rootObject: anObject.	"inform him about the root"
	dummy nextPut: anObject.
	coll := OrderedCollection new.
	dummy references keysDo: [:each |
		each class == aClass ifTrue: [coll add: each]].
	^ coll
]

{ #category : #'strings-conversion' }
SmartRefStream >> abstractStringx0 [

	^ String
]

{ #category : #'read write' }
SmartRefStream >> appendClassDefns [
	"Make this a fileOut format file.  For each UniClass mentioned, prepend its source code to the file.  Class name conflicts during reading will be resolved then.  Assume instVarInfo: has already been done."

| asciiStream |
asciiStream := (String new: 1024) writeStream.
byteStream position = 0 ifTrue: [
		"Type and Creator not to be text, so can attach correctly to an email msg"
	asciiStream header; timeStamp].

asciiStream cr; nextPutAll: '!ObjectScanner new initialize!'; cr; cr.

	"Append the object's raw data"
	asciiStream cr; cr; nextPutAll: '!self smartRefStream!'.
	byteStream nextPutAll: asciiStream contents asByteArray.		"get ready for objects"

]

{ #category : #'import image segment' }
SmartRefStream >> applyConversionMethodsTo: objectIn className: className varMap: varMap [
	"Modify the object's instance vars to have the proper values
for its new shape.  Mostly, fill in defaut values of new inst vars.
Can substitute an object of a different class.  (Beware: if
substituted, varMap will not be correct when the new object is asked
to convert.)"
	| anObject prevObject |

	self flag: #bobconv.

	anObject := objectIn.
	[
		prevObject := anObject.
		anObject := anObject convertToCurrentVersion: varMap
refStream: self.
		prevObject == anObject
	] whileFalse.
	^anObject
]

{ #category : #'class changed shape' }
SmartRefStream >> catalogValues: instVarList size: varsOnDisk [
	"Create a dictionary of (name -> value) for the inst vars of this reshaped object.  Indexed vars as (1 -> val) etc.  "

	| dict sz |
	dict := Dictionary new.
	2 to: instVarList size do: [:ind |
		dict at: (instVarList at: ind) put: self next].
	sz := varsOnDisk - (instVarList size - 1).
	1 to: sz do: [:ii | 
		dict at: ii put: self next].
	"Total number read MUST be equal to varsOnDisk!"
	sz > 0 ifTrue: [dict at: #SizeOfVariablePart put: sz].
	^ dict
]

{ #category : #'read write' }
SmartRefStream >> checkCrLf [
	| save isCrLf cc loneLf |
	"Watch for a file that has had all of its Cr's converted to CrLf's.  Some unpacking programs like Stuffit 5.0 do this by default!"

	save := byteStream position.
	isCrLf := false.  loneLf := false.
	cc := 0.
	350 timesRepeat: [ | prev |
		prev := cc.
		(cc := byteStream next) = 16r0A "Lf" ifTrue: [
			prev = 16r0D "Cr" ifTrue: [isCrLf := true] ifFalse: [loneLf := true]].
		].
	isCrLf & (loneLf not) ifTrue: [
		self inform: 'Carriage Returns in this file were converted to CrLfs 
by an evil unpacking utility.  Please set the preferences in 
StuffIt Expander to "do not convert file formats"'].
	byteStream position: save.

]

{ #category : #'import image segment' }
SmartRefStream >> checkFatalReshape: setOfClasses [
	| suspects |
	"Inform the user if any of these classes were reshaped.  A block has a method from the old system whose receiver is of this class.  The method's inst var references might be wrong.  OK if inst vars were only added."

	self flag: #bobconv.	

	setOfClasses isEmpty ifTrue: [^ self].
	suspects := OrderedCollection new.
	setOfClasses do: [:aClass | | newInstVars oldInstVars bad className |
		className := renamed keyAtValue: aClass name ifAbsent: [aClass name].
		oldInstVars := (structures at: className ifAbsent: [#(0)]) allButFirst.		"should be there"
		newInstVars := aClass allInstVarNames.
		oldInstVars size > newInstVars size ifTrue: [bad := true].
		oldInstVars size = newInstVars size ifTrue: [
			bad := oldInstVars ~= newInstVars].
		oldInstVars size < newInstVars size ifTrue: [
			bad := oldInstVars ~= (newInstVars copyFrom: 1 to: oldInstVars size)].
		bad ifTrue: [suspects add: aClass]].

	suspects isEmpty ifFalse: [
		self inform: ('Imported foreign methods will run on instances of:\',
			suspects asArray printString, 
			'\whose shape has changed.  Errors may occur.') withCRs].
]

{ #category : #'class changed shape' }
SmartRefStream >> conversionMethodsFor: classList [
	| list |
	"Each of these needs a conversion method.  Hard part is the comment in it.  Return a MessageSet."

	list := OrderedCollection new.
	classList do: [:cls | | oldStruct newStruct |
		oldStruct := structures at: cls name ifAbsent: [#()].
		newStruct := (Array with: cls classVersion), (cls allInstVarNames).
		self writeConversionMethodIn: cls fromInstVars: oldStruct to: newStruct 
				renamedFrom: nil.
		list add: cls name, ' convertToCurrentVersion:refStream:'.
		].

	^list.
]

{ #category : #'import image segment' }
SmartRefStream >> convert1: misShapenInst to: goodClass allVarMaps: allVarMaps [
	"Go through the normal instance conversion process and return a modern object."

	| className oldInstVars anObject varMap |

	self flag: #bobconv.	

	goodClass isVariable ifTrue: [
		goodClass error: 'shape change for variable class not implemented yet'
	].
	(misShapenInst class name beginsWith: 'Fake37') ifFalse: [self error: 'why mapping?'].
	className := (misShapenInst class name allButFirst: 6) asSymbol.
	oldInstVars := structures at: className.
	anObject := goodClass basicNew.

	varMap := Dictionary new.	"later, indexed vars as (1 -> val) etc."
	2 to: oldInstVars size do: [:ind |
		varMap at: (oldInstVars at: ind) put: (misShapenInst instVarAt: ind-1)].
	varMap at: #ClassName put: className.	"original"
	varMap at: #NewClassName put: goodClass name.	"new"
	self storeInstVarsIn: anObject from: varMap. 	"ones with the same names"
	allVarMaps at: misShapenInst put: varMap.
	^ anObject

]

{ #category : #'import image segment' }
SmartRefStream >> convert2: partiallyCorrectInst allVarMaps: allVarMaps [
	"Go through the normal instance conversion process and return a modern object."

	| className varMap |

	self flag: #bobconv.	

	varMap := allVarMaps at: partiallyCorrectInst.
	className := varMap at: #ClassName.	"original"
	^self applyConversionMethodsTo: partiallyCorrectInst className: className varMap: varMap.


]

{ #category : #'read write' }
SmartRefStream >> initKnownRenames [
	renamed
		at: #FlasherMorph put: #Flasher;
		at: #AlansTextPlusMorph put: #TextPlusMorph;
		at: #Project put: #MorphicProject;
		at: #Presenter put: #EtoysPresenter;
		at: #InputSensor put: #EventSensor;
		yourself
]

{ #category : #'read write' }
SmartRefStream >> initShapeDicts [
	"Initialize me. "

	self flag: #bobconv.	

	"These must stay constant.  When structures read in, then things can change."
	steady := {Array. Dictionary. Association. ByteString. SmallInteger. Character} asSet.

	renamed ifNil: [
		renamed := Dictionary new.  "(old class name symbol -> new class name)"
		renamedConv := Dictionary new "(oldClassNameSymbol -> conversionSelectorInNewClass)"
	].
	self initKnownRenames
]

{ #category : #'read write' }
SmartRefStream >> instVarInfo: anObject [
	"Return the object to write on the outgoing file that contains the structure of each class we are about to write out.  Must be an Array whose first element is 'class structure'.  Its second element is a Dictionary of pairs of the form #Rectangle -> #(<classVersion> 'origin' 'corner').  "

	"Make a pass through the objects, not writing, but recording the classes.  Construct a database of their inst vars and any version info (classVersion)."

	| dummy refs cls newSupers |
	structures := Dictionary new.
	superclasses := Dictionary new.
	dummy := ReferenceStream on: (DummyStream on: nil).
		"Write to a fake Stream, not a file"
	"Collect all objects"
	dummy rootObject: anObject.	"inform him about the root"
	dummy nextPut: anObject.
	refs := dummy references.
	objCount := refs size.		"for progress bar"
		"Note that Dictionary must not change its implementation!  If it does, how do we read this reading information?"
	(refs includesKey: #AnImageSegment) 
		ifFalse: [
			refs keysDo: [:each | 
				cls := each class.
				"cls isObsolete ifTrue: [self error: 'Trying to write ', cls name]."
				(cls class ~~ Metaclass) & ((self class isClassObsolete: cls) not) ifTrue: [
					structures at: cls name put: false]]]
		ifTrue: [self recordImageSegment: refs].
	"Save work by only computing inst vars once for each class"
	newSupers := Set new.
	structures at: #Point put: false.	"writeRectangle: does not put out class pointer"
	structures at: #Rectangle put: false.
	structures at: #LargePositiveInteger put: false.	"used in slow case of WordArray"
	structures keysDo: [:nm | 
		cls := (nm endsWith: ' class') 
			ifFalse: [Smalltalk at: nm]
			ifTrue: [(Smalltalk at: nm substrings first asSymbol) class].
		cls allSuperclasses do: [:aSuper |
			structures at: aSuper name ifAbsent: [newSupers add: aSuper name]]].
			"Don't modify structures during iteration"
	newSupers do: [:nm | structures at: nm put: 3].	"Get all superclasses into list"
	structures keysDo: [:nm | "Nothing added to classes during loop"
		cls := (nm endsWith: ' class') 
			ifFalse: [Smalltalk at: nm]
			ifTrue: [(Smalltalk at: nm substrings first asSymbol) class].
		structures at: nm put: 
			((Array with: cls classVersion), (cls allInstVarNames)).
		superclasses at: nm ifAbsentPut: [cls superclass ifNil: [ 'nil' ] ifNotNil: [ :s | s name ]]].
	(refs includesKey: #AnImageSegment) 
		ifTrue: [classInstVars := #()]
		ifFalse: [self saveClassInstVars].	"of UniClassses"
	^ (Array with: 'class structure' with: structures with: 'superclasses' with: superclasses)
]

{ #category : #'read write' }
SmartRefStream >> mapClass: incoming [
	"See if the old class named nm exists.  If so, return it.  If not, map it to a new class, and save the mapping in renamed.  "

	<hasLiteralTest: #isConversionSelector:>
	"To find this method as sender of all conversion methods"

	| cls oldVer sel nm |

	self flag: #bobconv.	


	nm := renamed at: incoming ifAbsent: [incoming].	"allow pre-mapping around collisions"
	(nm endsWith: ' class') 
		ifFalse: [cls := Smalltalk at: nm ifAbsent: [nil].
			cls ifNotNil: [^ cls]]  	"Known class.  It will know how to translate the instance."
		ifTrue: [cls := Smalltalk at: nm substrings first asSymbol ifAbsent: [nil].
			cls ifNotNil: [^ cls class]]. 	"Known class.  It will know how to translate the instance."
	oldVer := self versionSymbol: (structures at: nm).
	sel := nm asString.
	sel at: 1 put: (sel at: 1) asLowercase.
	sel := sel, oldVer.	"i.e. #rectangleoc4"
	Symbol hasInterned: sel ifTrue: [:symb | 
		(self class canUnderstand: sel asSymbol) ifTrue: [
			reshaped ifNil: [reshaped := Dictionary new].
			cls := self perform: sel asSymbol]].	"This class will take responsibility"
	cls ifNil: [cls := self writeClassRenameMethod: sel was: nm
					fromInstVars: (structures at: nm).
			   cls isString ifTrue: [cls := nil]].
	cls ifNotNil: [renamed at: nm put: cls name].
	^ cls

]

{ #category : #'import image segment' }
SmartRefStream >> mapClass: newClass origName: originalName [
	"See if instances changed shape.  If so, make a fake class for the old shape and return it.  Remember the original class name."

	| newName oldInstVars fakeClass |
	newClass isMeta ifTrue: [^ newClass].
	newName := newClass name.
	(steady includes: newClass) & (newName == originalName) ifTrue: [^ newClass].
		"instances in the segment have the right shape"
	oldInstVars := structures at: originalName ifAbsent: [
			self error: 'class is not in structures list'].	"Missing in object file"

	"Allow mapping from old to new string names"
	(newName == #ByteString and:[originalName == #String]) ifTrue:[^newClass].
	(newName == #WideString and:[originalName == #MultiString]) ifTrue:[^newClass].
	(newName == #WideSymbol and:[originalName == #MultiSymbol]) ifTrue:[^newClass].

	"Variable classes are not handled fully. This one is fine. --bf"
	newName == #MethodContext ifTrue: [^newClass].
	"As I hope are these?  --eem"
	(#(Context BlockClosure AdditionalMethodState) includes: newName) ifTrue:
		[^newClass].

	fakeClass := Object subclass: ('Fake37', originalName) asSymbol
		instanceVariableNames: (' ' join: oldInstVars allButFirst)
		classVariableNames: ''
		poolDictionaries: ''
		category: 'Obsolete'.
	ChangeSet current removeClassChanges: fakeClass name.	"reduce clutter"
	^ fakeClass

]

{ #category : #'read write' }
SmartRefStream >> moreObjects [
	"Return true if there appears to be another object following this one on the file."

	| byte |
	byteStream atEnd ifTrue: [^ false].	"off end of file"
	(byte := byteStream peek) ifNil: [^ false].	"off end of file"
	byte = 33 "$! asciiValue" ifTrue: [^ false].
	byte = 0 ifTrue: [^ false].
	^ byte <= RefTypes size		"between 1 and 16"
]

{ #category : #'strings-conversion' }
SmartRefStream >> multiStringx0 [

	^ WideString
]

{ #category : #'strings-conversion' }
SmartRefStream >> multiSymbolx0 [

	^ WideSymbol
]

{ #category : #'read write' }
SmartRefStream >> next [
	"Really write three objects: (version, class structure, object). But only when called from the outside.  "

	| version ss object |
	^ topCall == nil 
		ifTrue: 
			[topCall := #marked.
			version := super next.
			version class == SmallInteger ifFalse: [^ version].	
				"version number, else just a regular object, not in our format, "
			self checkCrLf.
			ss := super next.
			ss class == Array ifFalse: [^ ss].  "just a regular object"
			(ss at: 1) = 'class structure' ifFalse: [^ ss].
			structures := ss at: 2.
			superclasses := (ss size > 3 and: [(ss at: 3) = 'superclasses']) 
				ifTrue: [ss at: 4]		"class name -> superclass name"
				ifFalse: [Dictionary new].
			(self verifyStructure = 'conversion method needed') ifTrue: [^ nil].
			object := super next.	"all the action here"
			self restoreClassInstVars.		"for UniClasses. version 4"

			topCall := nil.	"reset it"
			object]
		ifFalse:
			[super next]

]

{ #category : #'read write' }
SmartRefStream >> nextAndClose [
	"Speedy way to grab one object.  Only use when we are inside an object binary file.  If used for the start of a SmartRefStream mixed code-and-object file, tell the user and then do the right thing."

	| obj |
	byteStream peek = ReferenceStream versionCode "4" ifFalse: [
		"OK it is a fileIn afterall..."
		self inform: 'Should be using fileInObjectAndCode'.
		byteStream ascii.
		byteStream fileIn.
		obj := SmartRefStream scannedObject.
		SmartRefStream scannedObject: nil.
		^ obj].

	obj := self next.
	self close.
	^ obj
]

{ #category : #'read write' }
SmartRefStream >> nextPut: anObject [
	"Really write three objects: (version, class structure, object).  But only when called from the outside.  If any instance-specific classes are present, prepend their source code.  byteStream will be in fileOut format.
	You can see an analysis of which objects are written out by doing: 
	(SmartRefStream statsOfSubObjects: anObject)
	(SmartRefStream tallyOfSubObjects: anObject)
	(SmartRefStream subObjects: anObject ofClass: aClass)"

| info |
topCall == nil 
	ifTrue:
		[topCall := anObject.
		'Please wait while objects are counted' 
			displayProgressFrom: 0 to: 10
			during: [:bar | info := self instVarInfo: anObject].
		self appendClassDefns.	"For instance-specific classes"
		'Writing an object file'
			displayProgressFrom: 0 to: objCount*4	"estimate"
			during: [:bar |
				objCount := 0.
				progressBar := bar.
				self setStream: byteStream reading: false.
					"set basePos, but keep any class renames"
				super nextPut: ReferenceStream versionCode.
				super nextPut: info.
				super nextPut: anObject.		"<- the real writing"
				classInstVars size > 0 ifTrue: [super nextPut: classInstVars]].
					"Note: the terminator, $!, is not doubled inside object data"
		"references is an IDict of every object that got written"
		byteStream ascii.
		byteStream nextPutAll: '!'; cr; cr.
		byteStream padToEndWith: $ .	"really want to truncate file, but can't"
		topCall := progressBar := nil]	"reset it"
	ifFalse:
		[super nextPut: anObject.
		progressBar ifNotNil: [progressBar value: (objCount := objCount + 1)]].
		"return the argument - added by kwl"
	^ anObject

]

{ #category : #'read write' }
SmartRefStream >> nextPutObjOnly: anObject [
	"Really write three objects: (version, class structure, object).  But only when called from the outside.  Not in fileOut format.  No class definitions will be written for instance-specific classes.  Error if find one.  (Use nextPut: instead)"

	| info |
	topCall == nil 
		ifTrue:
			[topCall := anObject.
			super nextPut: ReferenceStream versionCode.
			'Please wait while objects are counted'
				displayProgressFrom: 0 to: 10
				during: [:bar |
					info := self instVarInfo: anObject].
			'Writing an object file'
				displayProgressFrom: 0 to: objCount*4	"estimate"
				during: [:bar |
					objCount := 0.
					progressBar := bar.
					super nextPut: info.
					super nextPut: anObject.	"<- the real writing"
					"Class inst vars not written here!"].
			"references is an IDict of every object that got written
			(in case you want to take statistics)"
			"Transcript cr; show: structures keys printString."		"debug"
			topCall := progressBar := nil]	"reset it"
		ifFalse:
			[super nextPut: anObject.
			progressBar ifNotNil: [progressBar value: (objCount := objCount + 1)]].
]

{ #category : #'read write' }
SmartRefStream >> noHeader [
	"Signal that we've already dealt with the version and structure array, and are now reading objects."

	topCall := #marked.

]

{ #category : #'read write' }
SmartRefStream >> readInstance [
	"Read the contents of an arbitrary instance.
	 ASSUMES: readDataFrom:size: sends me beginReference: after it
	   instantiates the new object but before reading nested objects.
	 NOTE: We must restore the current reference position after
	   recursive calls to next.
Three cases for files from older versions of the system:
1) Class has not changed shape, read it straight.
2) Class has changed instance variables (or needs fixup).  Call a particular method to do it.
3) There is a new class instead.  Find it, call a particular method to read.
	All classes used to construct the structures dictionary *itself* need to be in 'steady' and they must not change!  See setStream:"
	| instSize className refPosn |

	instSize := (byteStream nextNumber: 4) - 1.
	refPosn := self getCurrentReference.
	className := self next asSymbol.
	^ self readInstanceSize: instSize clsname: className refPosn: refPosn

]

{ #category : #'read write' }
SmartRefStream >> readInstanceSize: instSize clsname: className refPosn: refPosn [
	"The common code to read the contents of an arbitrary instance.
	 ASSUMES: readDataFrom:size: sends me beginReference: after it
	   instantiates the new object but before reading nested objects.
	 NOTE: We must restore the current reference position after
	   recursive calls to next.
Three cases for files from older versions of the system:
1) Class has not changed shape, read it straight.
2) Class has changed instance variables (or needs fixup).  Call a particular method to do it.
3) There is a new class instead.  Find it, call a particular method to read.
	All classes used to construct the structures dictionary *itself* need to be in 'steady' and they must not change!  See setStream:"
	| anObject newName newClass dict oldInstVars isMultiSymbol |

	self flag: #bobconv.	

	self setCurrentReference: refPosn.  "remember pos before readDataFrom:size:"
	newName := renamed at: className ifAbsent: [className].
	isMultiSymbol := newName = #MultiSymbol or: [newName = #WideSymbol].
	"isMultiSymbol ifTrue: [self halt]."
	newClass := Smalltalk at: newName asSymbol.
	(steady includes: newClass) & (newName == className) ifTrue: [
		anObject := newClass isImmediateClass
			ifTrue: [newClass readImmediateFrom: self size: instSize]
			ifFalse: [anObject := newClass isVariable 	"Create object here"
					ifFalse: [newClass basicNew]
					ifTrue: [newClass basicNew: instSize - (newClass instSize)].
				anObject readDataFrom: self size: instSize].
		
		self setCurrentReference: refPosn.  "before returning to next"
		isMultiSymbol ifTrue: [^ Symbol intern: anObject asString].
		^ anObject].
	oldInstVars := structures at: className ifAbsent: [
			self error: 'class is not in structures list'].	"Missing in object file"
	anObject := newClass createFrom: self size: instSize version: oldInstVars.
		"only create the instance"
	self beginReference: anObject.
	dict := self catalogValues: oldInstVars size: instSize.
		"indexed vars as (1 -> val) etc."
	dict at: #ClassName put: className.	"so conversion method can know it"

	"Give each superclass a chance to make its changes"
	self storeInstVarsIn: anObject from: dict.	"ones with the same names"

	anObject := self applyConversionMethodsTo: anObject className: className varMap: dict.

	self setCurrentReference: refPosn.  "before returning to next"
	isMultiSymbol ifTrue: [^ Symbol intern: anObject asString].
	^ anObject
]

{ #category : #'read write' }
SmartRefStream >> readShortInst [
	"Instance has just one byte of size.  Class symbol is encoded in two bytes of file position.  See readInstance."
	| instSize className refPosn |

	instSize := (byteStream next) - 1.	"one byte of size"
	refPosn := self getCurrentReference.
	className := self readShortRef.	"class symbol in two bytes of file pos"
	^ self readInstanceSize: instSize clsname: className refPosn: refPosn

]

{ #category : #'read write' }
SmartRefStream >> readWordLike [
	| refPosn newClass anObject className |
	"Can be used by any class that is bits and not bytes (WordArray, Bitmap, SoundBuffer, etc)."

	refPosn := self getCurrentReference.
	className := self next asSymbol.
	className := renamed at: className ifAbsent: [className].
	newClass := Smalltalk at: className.
	anObject := newClass newFromStream: byteStream.
	"Size is number of long words."
	self setCurrentReference: refPosn.  "before returning to next"
	^ anObject

]

{ #category : #'read write' }
SmartRefStream >> recordImageSegment: refs [
	"Besides the objects being written out, record the structure of instances inside the image segment we are writing out."

	| list |
	"Do not record Player class inst vars.  They are in the segement."
	refs
		keysDo: [ :each | 
			| cls |
			cls := each class.
			(self class isClassObsolete: cls) ifTrue: [
				self error: 'Trying to write obsolete class ' , cls name ].
			cls class == Metaclass
				ifFalse: [ structures at: cls name put: false.
					(each isKindOf: ImageSegment)
						ifTrue: [ each outPointers
								do: [ :out | 
									(out isKindOf: Class)
										ifTrue: [ structures at: out instanceSide name put: false ].
									out class == DiskProxy
										ifTrue: [ out simpleGlobalOrNil
												ifNotNil: [ (out simpleGlobalOrNil isKindOf: Class)
														ifTrue: [ structures at: out simpleGlobalOrNil name put: false ] ] ] ]
							"each arrayOfRoots do: [:rr | (rr isKindOf: Class) ifTrue: [
							structures at: rr theNonMetaClass name put: false]]."
							"all classes in roots are local to seg" ] ] ].
	list := refs at: #BlockReceiverClasses ifAbsent: [ ^ self ].
	list do: [ :meta | structures at: meta name put: false ]
	"Just the metaclasses whose instances are block receivers.  Otherwise metaclasses are not allowed."
]

{ #category : #'read write' }
SmartRefStream >> renamed [

	self flag: #bobconv.	


	^ renamed
]

{ #category : #'read write' }
SmartRefStream >> renamedConv [
	self flag: #bobconv.	


	^ renamedConv
]

{ #category : #'import image segment' }
SmartRefStream >> reshapedClassesIn: outPointers [
	"Look for classes in the outPointer array that have changed shape.  Make a fake class for the old shape.  Return a dictionary mapping Fake classes to Real classes.  Substitute fake classes for real ones in outPointers."

	| mapFakeClassesToReal |

	self flag: #bobconv.	
	"make sure we don't try to convert classes not in structures to renamed classes"
	renamed keysDo:[ :renamedClass | structures at: renamedClass ifAbsent:[ renamed removeKey: renamedClass]].

	mapFakeClassesToReal := IdentityDictionary new.
	outPointers withIndexDo: [:outp :ind | | originalName fakeCls | 
		outp isBehavior ifTrue: [
			originalName := renamed keyAtValue: outp name
				ifAbsent: [renamedConv at: ind ifAbsent: [outp name]].
			"in DiskProxy>>comeFullyUpOnReload: we saved the name at the index"
			fakeCls := self mapClass: outp origName: originalName.
			fakeCls == outp ifFalse: [
				mapFakeClassesToReal at: fakeCls put: outp.
				outPointers at: ind put: fakeCls]]].
	^ mapFakeClassesToReal
]

{ #category : #'read write' }
SmartRefStream >> restoreClassInstVars [
	"Install the values of the class instance variables of UniClasses
(i.e. scripts slotInfo).  classInstVars is ((#Player25 scripts slotInfo)
...).  Thank you Mark Wai for the bug fix."

	| normal trans classPlayer |

	self flag: #bobconv.	

	classPlayer := Smalltalk at: #Player ifAbsent:[^self].

	self moreObjects ifFalse: [^ self]. 	"are no UniClasses with class inst vars"
	classInstVars := super next.	"Array of arrays"
	normal := Object class instSize.	"might give trouble if Player class superclass changes size"
	(structures at: #Player ifAbsent: [#()]) = #(0 'dependents' 'costume') ifTrue:
		[trans := 1].	"now (0 costume costumes).  Do the conversion of Player class
			inst vars in Update 509."
	classInstVars do: [:list | | aName newCls rList newName start |
		aName := (list at: 1) asSymbol.
		rList := list.
		newName := renamed at: aName ifAbsent: [aName].
		newCls := Smalltalk at: newName
				ifAbsent: [self error: 'UniClass definition missing'].
		("old conversion" trans = 1 and: [newCls inheritsFrom: classPlayer]) ifTrue: [
			"remove costumeDictionary from Player class inst vars"
			rList := rList asOrderedCollection.
			rList removeAt: 4].	"costumeDictionary's value"
		start := list second = 'Update to read classPool' ifTrue: [4] ifFalse: [2].
		newCls class instSize = (normal + (rList size) - start + 1) ifFalse:
			[self error: 'UniClass superclass class has changed size'].
			"Need to install a conversion method mechanism"
		start = 4 ifTrue: [newCls instVarAt: normal - 1 "classPool" put: (list at: 3)].
		start to: rList size do: [:ii |
			newCls instVarAt: normal + ii - start + 1 put: (rList at: ii)]].

]

{ #category : #'read write' }
SmartRefStream >> saveClassInstVars [
	"Install the values of the instance variables of UniClasses.
classInstVars is an array of arrays (#Player3 (Player3 class's inst var
scripts) (Player3 class's inst var slotInfo) ...) "

	| normal clsPoolIndex |
	classInstVars := OrderedCollection new: 100.
	normal := Object class instSize.
	clsPoolIndex := Object class allInstVarNames indexOf: 'classPool'.
	classInstVars := classInstVars asArray.
	
]

{ #category : #'read write' }
SmartRefStream >> scanFrom: aByteStream [
	"During a code fileIn, we need to read in an object, and stash it in ScannedObject.  "

	self setStream: aByteStream reading: true.
	ScannedObject := self next.
	byteStream ascii.
	byteStream next == $! ifFalse: [
		byteStream close.
		self error: 'Object did not end correctly']. 
	"caller will close the byteStream"
	"HandMorph.readMorphFile will retrieve the ScannedObject"
]

{ #category : #'read write' }
SmartRefStream >> scanFrom: aByteStream environment: anEnvironment [
	^ self scanFrom: aByteStream
]

{ #category : #'read write' }
SmartRefStream >> setStream: aStream [
	"Initialize me. "

	self flag: #bobconv.	

	super setStream: aStream.
	self initShapeDicts.


]

{ #category : #'read write' }
SmartRefStream >> setStream: aStream reading: isReading [
	"Initialize me. "

	self flag: #bobconv.	

	super setStream: aStream reading: isReading.
	isReading ifFalse: [^ false].
	self initShapeDicts.


]

{ #category : #'class changed shape' }
SmartRefStream >> storeInstVarsIn: anObject from: dict [
	"For instance variables with the same names, store them in the new instance.  Values in variable-length part also.  This is NOT the normal inst var transfer!  See Object.readDataFrom:size:.  This is for when inst var names have changed and some additional conversion is needed.  Here we handle the unchanged vars.  "

	(anObject class allInstVarNames) doWithIndex: [:varName :index |
		(dict includesKey: varName) ifTrue: [
			anObject instVarAt: index put: (dict at: varName)]].
	"variable part"
	(dict includesKey: #SizeOfVariablePart) ifFalse: [^ anObject].
	1 to: (dict at: #SizeOfVariablePart) do: [:index | 
		anObject basicAt: index put: (dict at: index)].
	^ anObject
]

{ #category : #'read write' }
SmartRefStream >> structures [
	^ structures
]

{ #category : #accessing }
SmartRefStream >> structures: anObject [
	structures := anObject
]

{ #category : #'read write' }
SmartRefStream >> superclasses [
	^superclasses
]

{ #category : #accessing }
SmartRefStream >> superclasses: anObject [
	superclasses := anObject
]

{ #category : #'read write' }
SmartRefStream >> verifyStructure [
	"Compare the incoming inst var name lists with the existing classes.  Prepare tables that will help to restructure those who need it (renamed, reshaped, steady).    If all superclasses are recorded in the file, only compare inst vars of this class, not of superclasses.  They will get their turn.  "


	| converting |

	self flag: #bobconv.	

	converting := OrderedCollection new.
	structures keysDo: [:nm "an old className (symbol)" | | newClass newList oldList |
		"For missing classes, there needs to be a method in SmartRefStream like 
			#rectangleoc2 that returns the new class."
		newClass := self mapClass: nm.	   "does (renamed at: nm put: newClass name)"
		newClass isString ifTrue: [^ newClass].  "error, fileIn needed"
		newList := (Array with: newClass classVersion), (newClass allInstVarNames).
		oldList := structures at: nm.
		newList = oldList 
			ifTrue: [steady add: newClass]  "read it in as written"
			ifFalse: [converting add: newClass name]
	].
	false & converting isEmpty not ifTrue: ["debug" 
			self inform: 'These classes are being converted from existing methods:\' withCRs,
				converting asArray printString].

]

{ #category : #'read write' }
SmartRefStream >> versionSymbol: instVarList [
	"Create the symbolic code (like a version number) for this class in some older version.  First initials of all the inst vars, followed by the class version number.  Returns a string, caller makes it into a compound selector.  "

	| str |
	str := instVarList size = 1 ifFalse: [''] ifTrue: ['x'].		"at least one letter"
	2 to: instVarList size do: [:ind |
		str := str, (instVarList at: ind) first asString].
	str := str, instVarList first printString.	"the number"
	^ str

" | list | list := (Array with: Paragraph classVersion), (Paragraph alistInstVarNames).
(SmartRefStream  on: (DummyStream on: nil)) versionSymbol: list
"
]

{ #category : #'class changed shape' }
SmartRefStream >> writeClassRename: newName was: oldName [
	"Write a method that tells which modern class to map instances to."
	| oldVer sel code |

	oldVer := self versionSymbol: (structures at: oldName).
	sel := oldName asString.
	sel at: 1 put: (sel at: 1) asLowercase.
	sel := sel, oldVer.	"i.e. #rectangleoc4"

	code := WriteStream on: (String new: 500).
	code nextPutAll: sel; cr.
	code cr; tab; nextPutAll: '^ ', newName.	"Return new class"

	self class compile: code contents classified: 'conversion'.


]

{ #category : #'class changed shape' }
SmartRefStream >> writeClassRenameMethod: sel was: oldName fromInstVars: oldList [
	"The class coming is unknown.  Ask the user for the existing class it maps to.  If got one, write a method, and restart the obj fileIn.  If none, write a dummy method and get the user to complete it later.  "

| tell choice  newName answ code |

	self flag: #bobconv.	


tell := 'Reading an instance of ', oldName, '.
Which modern class should it translate to?'.
answ := (UIManager default 
		chooseFrom: #('Let me type the name now' 'Let me think about it'
'Let me find a conversion file on the disk') 
		title: tell). 

answ = 1 ifTrue: [
	tell := 'Name of the modern class {1} should translate to:' translated format: {oldName}.
	choice := UIManager default request: tell.		"class name"
	(choice size = 0) 
		ifTrue: [answ := 'conversion method needed']
		ifFalse: [newName := choice.
			answ := Smalltalk at: newName asSymbol 
				ifAbsent: ['conversion method needed'].
			answ isString ifFalse: [renamed at: oldName asSymbol put: answ name]]].
(answ = 3) | (answ = 0) ifTrue: [self close.
		^ 'conversion method needed'].
answ = 2 ifTrue: [answ := 'conversion method needed'].
answ = 'conversion method needed' ifTrue: [
		self close.  
		newName := 'PutNewClassHere'].

code := WriteStream on: (String new: 500).
code nextPutAll: sel; cr.
code cr; tab; nextPutAll: '^ ', newName.	"Return new class"

self class compile: code contents classified: 'conversion'.

newName = 'PutNewClassHere' ifTrue: [
	self inform: 'Please complete the following method and 
then read-in the object file again.'.
	SystemNavigation default browseAllImplementorsOf: sel asSymbol]. 

	"The class version number only needs to change under one specific circumstance.  That is when the first letters of the instance variables have stayed the same, but their meaning has changed.  A conversion method is needed, but this system does not know it.  
	If this is true for class Foo, define classVersion in Foo class.  
	Beware of previous object fileouts already written after the change in meaning, but before bumping the version number.  They have the old (wrong) version number, say 2.  If this is true, your method must be able to test the data and successfully read files that say version 2 but are really 3."

	^ answ
]

{ #category : #'class changed shape' }
SmartRefStream >> writeConversionMethod: sel class: newClass was: oldName fromInstVars: oldList to: newList [
	"The method convertToCurrentVersion:refStream: was not found in newClass.  Write a default conversion method for the author to modify."

	| code newOthers oldOthers copied |

	code := WriteStream on: (String new: 500).
	code nextPutAll: 'convertToCurrentVersion: varDict refStream: smartRefStrm'; cr; tab.
	newOthers := newList asOrderedCollection "copy".
	oldOthers := oldList asOrderedCollection "copy".
	copied := OrderedCollection new.
	newList do: [:instVar |
		(oldList includes: instVar) ifTrue: [
			instVar isInteger ifFalse: [copied add: instVar].
			newOthers remove: instVar.
			oldOthers remove: instVar]].
	code nextPutAll: '"These variables are automatically stored into the new instance '.
	code nextPutAll: copied asArray printString; nextPut: $. .
	code cr; tab; nextPutAll: 'This method is for additional changes.'; 
		nextPutAll: ' Use statements like (foo := varDict at: ''foo'')."'; cr; cr; tab.
	(newOthers size = 0) & (oldOthers size = 0) ifTrue: [^ self].
		"Instance variables are the same.  Only the order changed.  No conversion needed."
	(newOthers size > 0) ifTrue: [code nextPutAll: '"New variables: ', newOthers asArray printString, '  If a non-nil value is needed, please assign it."\' withCRs].
	(oldOthers size > 0) ifTrue: [code nextPutAll: '	"These are going away ', oldOthers asArray printString, '.  Possibly store their info in some other variable?"'].

	code cr; tab.
	code nextPutAll: '^ super convertToCurrentVersion: varDict refStream: smartRefStrm'.
	newClass compile: code contents classified: 'object fileIn'.


	"If you write a conversion method beware that the class may need a version number change.  This only happens when two conversion methods in the same class have the same selector name.  (A) The inst var lists of the new and old versions intials as some older set of new and old inst var lists.  or (B) Twice in a row, the class needs a conversion method, but the inst vars stay the same the whole time.  (For an internal format change.)
	If either is the case, fileouts already written with the old (wrong) version number, say 2.  Your method must be able to read files that say version 2 but are really 3, until you expunge the erroneous version 2 files from the universe."

 
]

{ #category : #'class changed shape' }
SmartRefStream >> writeConversionMethodIn: newClass fromInstVars: oldList to: newList renamedFrom: oldName [
	"The method convertToCurrentVersion:refStream: was not found in newClass.  Write a default conversion method for the author to modify.  If method exists, append new info into the end."

	| code newOthers oldOthers copied newCode |

	newOthers := newList asOrderedCollection "copy".
	oldOthers := oldList asOrderedCollection "copy".
	copied := OrderedCollection new.
	newList do: [:instVar |
		(oldList includes: instVar) ifTrue: [
			instVar isInteger ifFalse: [copied add: instVar].
			newOthers remove: instVar.
			oldOthers remove: instVar]].
	code := WriteStream on: (String new: 500).
	code cr; cr; tab; nextPutAll: '"From ', SystemVersion current version, ' [', Smalltalk lastUpdateString;
			nextPutAll: '] on ', Date today printString, '"'; cr.
	code tab; nextPutAll: '"These variables are automatically stored into the new instance: '.
	code nextPutAll: copied asArray printString; nextPut: $.; cr.
	code tab; nextPutAll: 'Test for this particular conversion.'; 
		nextPutAll: '  Get values using expressions like (varDict at: ''foo'')."'; cr; cr.
	(newOthers size = 0) & (oldOthers size = 0) & (oldName == nil) ifTrue: [^ self].
		"Instance variables are the same.  Only the order changed.  No conversion needed."
	(newOthers size > 0) ifTrue: [
		code tab; nextPutAll: '"New variables: ', newOthers asArray printString, 
			'.  If a non-nil value is needed, please assign it."'; cr].
	(oldOthers size > 0) ifTrue: [
		code tab; nextPutAll: '"These are going away ', oldOthers asArray printString, 
			'.  Possibly store their info in some other variable?"'; cr].
	oldName ifNotNil: [
		code tab; nextPutAll: '"Test for instances of class ', oldName, '.'; cr.
		code tab; nextPutAll: 'Instance vars with the same name have been moved here."'; cr.
		].
	code tab; nextPutAll: '"Move your code above the ^ super...  Delete extra comments."'; cr. 

	(newClass includesSelector: #convertToCurrentVersion:refStream:) 
		ifTrue: ["append to old methods"
			newCode := (newClass sourceCodeAt: #convertToCurrentVersion:refStream:),
				code contents]
		ifFalse: ["new method"
			newCode := 'convertToCurrentVersion: varDict refStream: smartRefStrm',
				code contents, 
				'	^ super convertToCurrentVersion: varDict refStream: smartRefStrm'].
	newClass compile: newCode classified: 'object fileIn'.


	"If you write a conversion method beware that the class may need a version number change.  This only happens when two conversion methods in the same class have the same selector name.  (A) The inst var lists of the new and old versions intials as some older set of new and old inst var lists.  or (B) Twice in a row, the class needs a conversion method, but the inst vars stay the same the whole time.  (For an internal format change.)
	If either is the case, fileouts already written with the old (wrong) version number, say 2.  Your method must be able to read files that say version 2 but are really 3, until you expunge the erroneous version 2 files from the universe."

 
]
