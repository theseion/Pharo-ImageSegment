"
I represent a segment of Squeak address space.  I am created from an
array of root objects.  After storing, my segment contains a binary
encoding of every object accessible from my roots but not otherwise
accessible from anywhere else in the system.  My segment contains
outward pointers that are indices into my table of outPointers.
On load my segment is converted back into objects and becommed
into an Array of the loaded objects, so they can be enumerated.

I have two concrete subclasses, NativeImageSegment and
LegacyImageSegment.  NativeImageSegment uses a pair of primitives,
one to create a segment and one to load it. LegacyImageSegment
implements the load primitive for the older Squeak memory format
(sometimes called ""v3"") but uses pure Smalltalk code.

	The main use of ImageSegments is to store Projects.  A dummy
version of SmartRefStream traverses the Project.  Everything it finds
is classified as either an object that is owned by the project (only
pointed to inside the project), or an object outside the project that
is pointed to from inside the project.  The objects that are
completely owned by the project are compressed into pure binary form
in an ImageSegment.  The outside objects are put in the 'outPointers'
array.  The entire ImageSegment (binary part plus outPointers) is
encoded in a SmartRefStream, and saved on the disk.  (aProject
exportSegmentWithChangeSet:fileName:directory:) calls (anImageSegment
writeForExportWithSources:inDirectory:changeSet:).
	Note that every object inside the project is put into the
segment's arrayOfRoots.  This is because a dummy SmartRefStream to
scan the project, in order to make intelligent decisions about what
belongs in the project.
	See Project's class comment for what messages are sent to
objects as they are unpacked in a new image.

---- Older Details ------

	The primary kind of image segment is an Export Segment.  It
can be saved on a server and read into a completely different Squeak
image.
Old way to create one:
(ImageSegment new copyFromRootsForExport: (Array with: Baz with: Baz class))
		writeForExport: 'myFile.extSeg'.
Old way to create one for a project:
	(Project named: 'Play With Me - 3') exportSegment.
To read it into another image:  Select 'myFile.extSeg' in a FileList,
Menu 'load as project'.  It will install its classes automatically.
If you need to see the roots array, it is temporarily stored in
(SmartRefStream scannedObject).

Most of 'states' of an ImageSegment are not used to export a project,
and have been abandoned.

	When a segment is written out onto a file, it goes in a
folder called <image name>_segs.  If your image is called
""Squeak2.6.image"", the folder ""Squeak2.6_segs"" must accompany the
image whenever your move, copy, or rename it.
	Whenever a Class is in arrayOfRoots, its class (aClass class)
must also be in the arrayOfRoots.
	There are two kinds of image segments.  Normal image segments
are a piece of a specific Squeak image, and can only be read back
into that image.  The image holds the array of outPointers that are
necessary to turn the bits in the file into objects.
	To put out a normal segment that holds a Project (not the
current project), execute (Project named: 'xxx') storeSegment.


arrayOfRoots	The objects that head the tree we will trace.
segment			The WordArray of raw bits of all objects in the tree.
outPointers		Oops of all objects outside the segment
pointed to from inside.
state			(see below)
segmentName	Its basic name.  Often the name of a Project.
fileName		The local name of the file.  'Foo-23.seg'
userRootCnt		number of roots submitted by caller.  Extras
are added in preparation for saving.

state that an ImageSegment may exist in...

#activeCopy			(has been copied, with the intent to
become active)
arrayOfRoots, segment, and outPointers have been created by
copyFromRoots:.  The tree of objects has been encoded in the segment,
but those objects are still present in the Squeak system.

#active				(segment is actively holding objects)
The segment is now the only holder of tree of objects.  Each of the
original roots has been transmuted into an ImageSegmentRootStub that
refers back to this image segment.  The original objects in the
segment will all be garbageCollected.

#onFile
The segment has been written out to a file and replaced by a file
pointer.  Only ImageSegmentRootStubs and the array of outPointers
remains in the image.  To get this far:
(ImageSegment new copyFromRoots: (Array with: Baz with: Baz class))
		writeToFile: 'myFile.seg'.

#inactive
The segment has been brought back into memory and turned back into
objects.  rootsArray is set, but the segment is invalid.

#onFileWithSymbols
The segment has been written out to a file, along with the text of
all the symbols in the outPointers array, and replaced by a file
pointer.  This reduces the size of the outPointers array, and also
allows the system to reclaim any symbols that are not referred to
from elsewhere in the image.  The specific format used is that of a
literal array as follows:
	#(symbol1 symbol2 # symbol3 symbol4 'symbolWithSpaces' # symbol5).
In this case, the original outPointers array was 8 long, but the
compacted table of outPointers retains only two entries.  These get
inserted in place of the #'s in the array of symbols after it is read
back in.  Symbols with embedded spaces or other strange characters
are written as strings, and converted back to symbols when read back
in.  The symbol # is never written out.
	NOTE: All IdentitySets or dictionaries must be rehashed when
being read back from this format.  The symbols are effectively
internal.  (No, not if read back into same image.  If a different
image, then use #imported.  -tk)

#imported
The segment is on an external file or just read in from one.  The
segment and outPointers are meant to be read into a foreign image.
In this form, the image segment can be read from a URL, and
installed.  A copy of the original array of root objects is
constructed, with former outPointers bound to existing objects in the
host system.
	(Any Class inside the segment MUST be in the arrayOfRoots.
This is so its association can be inserted into Smalltalk.  The
class's metaclass must be in roots also.  Methods that are in
outPointers because blocks point at them, were found and added to the
roots.
	All IdentitySets and dictionaries are rehashed when being
read back from exported segments.)


To discover why only some of the objects in a project are being
written out, try this (***Destructive Test***).  This breaks lots of
backpointers in the target project, and puts up an array of
suspicious objects, a list of the classes of the outPointers, and a
debugger.
""Close any transcripts in the target project""
World currentHand objectToPaste ifNotNil: [
	self inform: 'Hand is holding a Morph in its paste buffer:\' withCRs,
		World currentHand objectToPaste printString].
PV := Project named: 'xxxx'.
(IS := ImageSegment new) findRogueRootsImSeg:
	(Array with: PV world presenter with: PV world).
IS findOwnersOutPtrs.	""Optionally: write a file with owner chains""
""Quit and DO NOT save""

When an export image segment is brought into an image, it is like an
image starting up.  Certain startUp messages need to be run.  These
are byte and word reversals for nonPointer data that comes from a
machine of the opposite endianness.  #startUpProc passes over all
objects in the segment, and:
	The first time an instance of class X is encountered, (msg :=
X startUpFrom: anImageSegment) is sent.  If msg is nil, the usual
case, it means that instances of X do not need special work.  X is
included in the IdentitySet, noStartUpNeeded.  If msg is not nil,
store it in the dictionary, startUps (aClass -> aMessage).
	When a later instance of X is encountered, if X is in
noStartUpNeeded, do nothing.  If X is in startUps, send the message
to the instance.  Typically this is a message like #swapShortObjects.
	Every class that implements #startUp, should see if it needs
a parallel implementation of #startUpFrom:.  
"
Class {
	#name : #ImageSegment,
	#superclass : #Object,
	#instVars : [
		'arrayOfRoots',
		'segment',
		'outPointers',
		'state',
		'segmentName',
		'fileName',
		'userRootCnt',
		'renamedClasses'
	],
	#classVars : [
		'RecentlyRenamedClasses'
	],
	#category : #'System-Object Storage'
}

{ #category : #'fileIn/Out' }
ImageSegment class >> copyFromRootsForExport: rootArray [
	"When possible, use copySmartRootsExport:. This way may not copy a complete tree
	 of objects. Add to roots: all of the methods pointed to from the outside by blocks."
	^NativeImageSegment new copyFromRootsForExport: rootArray
]

{ #category : #'fileIn/Out' }
ImageSegment class >> copyFromRootsLocalFileFor: rootArray sizeHint: segSize [
	"If the roots include a World, add its Player classes to the roots."
	^NativeImageSegment new copyFromRootsLocalFileFor: rootArray sizeHint: segSize
]

{ #category : #'fileIn/Out' }
ImageSegment class >> copySmartRootsExport: rootArray [
	"Use SmartRefStream to find the object.  Make them all roots.  Create the segment in memory.  Project should be in first five objects in rootArray."
	^NativeImageSegment new copySmartRootsExport: rootArray 
]

{ #category : #'fileIn/Out' }
ImageSegment class >> folder [
	| im |
	"Full path name of segments folder.  Be sure to duplicate and rename the folder when you duplicate and rename an image.  Is $_ legal in all file systems?"

	im := Smalltalk imageName.
	^ (im copyFrom: 1 to: im size - 6 "'.image' size"), '_segs'
]

{ #category : #'fileIn/Out' }
ImageSegment >> acceptSingleMethodSource: aDictionary [

	| oldClassInfo oldClassName ismeta newName actualClass selector |
	oldClassInfo := (aDictionary at: #oldClassName) findTokens: ' '.	"'Class' or 'Class class'"
	oldClassName := oldClassInfo first asSymbol.
	ismeta := oldClassInfo size > 1.

	"must use class var since we may not be the same guy who did the initial work"

	newName := RecentlyRenamedClasses ifNil: [
		oldClassName
	] ifNotNil: [
		RecentlyRenamedClasses at: oldClassName ifAbsent: [oldClassName]
	].
	actualClass := Smalltalk at: newName.
	ismeta ifTrue: [actualClass := actualClass class].
	selector := actualClass newParser parseSelector: (aDictionary at: #methodText).
	(actualClass compiledMethodAt: selector ifAbsent: [^self "hosed input"]) 
		putSource: (aDictionary at: #methodText)
		fromParseNode: nil
		class: actualClass
		category: (aDictionary at: #category)
		withStamp: (aDictionary at: #changeStamp)
		inFile: 2
		priorMethod: nil.

]

{ #category : #access }
ImageSegment >> allObjectsDo: aBlock [
	"Enumerate all objects that came from this segment.  NOTE this assumes that the segment was created (and extracted).  After the segment has been installed (install), this method allows you to enumerate its objects."
	self checkAndReportLoadError.
	segment do: aBlock
]

{ #category : #access }
ImageSegment >> arrayOfRoots [
	^ arrayOfRoots
]

{ #category : #access }
ImageSegment >> arrayOfRoots: array [
	arrayOfRoots := array
]

{ #category : #'error checking' }
ImageSegment >> checkAndReportLoadError [
	"Check that the load has occurred.  A side-efect of the load primitive is to become
	 the segment into an Array of the loaded objects, so they can be enumerated.  If
	 this hasn't happened also check if the segment is a zero-length word array which
	 indicates we're running on an older Spur VM that doesn't do the become."
	segment class isPointers ifTrue: [^self]. "ok"
	(segment class == WordArrayForSegment
	 and: [segment size = 0]) ifTrue:
		[^self error: 'The load primitive has not becomed segment into an Array of the loaded objects. \Please upgrade your virtual machine to one that does this.' withCRs].
	^self error: 'Segment has not been becommed into the loaded objects'
]

{ #category : #fileIn }
ImageSegment >> comeFullyUpOnReload: smartRefStream [
	"fix up the objects in the segment that changed size.  An object in the segment is the wrong size for the modern version of the class. Construct a fake class that is the old size.  Replace the modern class with the old one in outPointers.  Load the segment. Traverse the instances, making new instances by copying fields, and running conversion messages.  Keep the new instances.  Bulk forward become the old to the new.  Let go of the fake objects and classes.
	After the install (below), arrayOfRoots is filled in. Globalize new classes.  Caller may want to do some special install on certain objects in arrayOfRoots.
	May want to write the segment out to disk in its new form."

	| mapFakeClassesToReal receiverClasses forgetDoItsClass endianness |

	forgetDoItsClass := Set new.
	RecentlyRenamedClasses := nil.		"in case old data hanging around"
	mapFakeClassesToReal := smartRefStream reshapedClassesIn: outPointers.
		"Dictionary of just the ones that change shape. Substitute them in outPointers."
	self fixCapitalizationOfSymbols.
	endianness := self endianness.
	segment := self loadSegmentFrom: segment outPointers: outPointers.
	arrayOfRoots := segment first.
	mapFakeClassesToReal isEmpty ifFalse: [
		self reshapeClasses: mapFakeClassesToReal refStream: smartRefStream
	].
	"When a Project is stored, arrayOfRoots has all objects in the project, except those in outPointers"
	arrayOfRoots do: [:importedObject |
		((importedObject isMemberOf: WideString) or: [importedObject isMemberOf: WideSymbol]) ifTrue: [
			importedObject mutateJISX0208StringToUnicode.
			importedObject class = WideSymbol ifTrue: [
				"self halt."
				Symbol hasInterned: importedObject asString ifTrue: [:multiSymbol |
					multiSymbol == importedObject ifFalse: [
						importedObject becomeForward: multiSymbol.
					].
				].
			].
		].
	].

	receiverClasses := self restoreEndianness: endianness ~~ EndianDetector endianness.		"rehash sets"
	smartRefStream checkFatalReshape: receiverClasses.

	"Classes in this segment."
	arrayOfRoots do: [:importedObject |
		importedObject class class == Metaclass ifTrue: [forgetDoItsClass add: importedObject. self  declare: importedObject]].

	mapFakeClassesToReal isEmpty ifFalse: [
		mapFakeClassesToReal keysAndValuesDo: [:aFake :aReal |
			aFake removeFromSystemUnlogged.
			aFake becomeForward: aReal].
		SystemOrganization removeEmptyCategories].
	forgetDoItsClass do: [:c |
		c
			removeSelector: #DoIt;
			removeSelector: #DoIt: ].
	"^ self"

]

{ #category : #fileIn }
ImageSegment >> declare: classThatIsARoot [

	| nameOnArrival |
	"The class just arrived in this segment.  How fit it into the Smalltalk dictionary?  If it had an association, that was installed with associationDeclareAt:."

	nameOnArrival := classThatIsARoot name.
	self declareAndPossiblyRename: classThatIsARoot.
	nameOnArrival == classThatIsARoot name ifTrue: [^self].
	renamedClasses ifNil: [RecentlyRenamedClasses := renamedClasses := Dictionary new].
	renamedClasses at: nameOnArrival put: classThatIsARoot name.


]

{ #category : #fileIn }
ImageSegment >> declareAndPossiblyRename: classThatIsARoot [
	| existing catInstaller |
	"The class just arrived in this segment.  How fit it into the Smalltalk dictionary?  If it had an association, that was installed with associationDeclareAt:."

	catInstaller := [
		classThatIsARoot superclass name == #Player 
			ifTrue: [classThatIsARoot category: Object categoryForUniclasses]
			ifFalse: [(classThatIsARoot superclass name beginsWith: 'WonderLandActor')
				ifTrue: [classThatIsARoot category: 'Balloon3D-UserObjects']
				ifFalse: [classThatIsARoot category: Object categoryForUniclasses]].
	].
	classThatIsARoot superclass addSubclass: classThatIsARoot.
	(Smalltalk includesKey: classThatIsARoot name) ifFalse: [
		"Class entry in Smalltalk not referred to in Segment, install anyway."
		catInstaller value.
		^ Smalltalk at: classThatIsARoot name put: classThatIsARoot].
	existing := Smalltalk at: classThatIsARoot name.
	existing xxxClass == ImageSegmentRootStub ifTrue: [
		"We are that segment!  Must ask it carefully!"
		catInstaller value.
		^ Smalltalk at: classThatIsARoot name put: classThatIsARoot].
	existing == false | (existing == nil) ifTrue: [
		"association is in outPointers, just installed"
		catInstaller value.
		^ Smalltalk at: classThatIsARoot name put: classThatIsARoot].
	"Conflict with existing global or copy of the class"
	(existing isKindOf: Class) ifTrue: [
		"Take the incoming one"
		self inform: 'Using newly arrived version of ', classThatIsARoot name.
		classThatIsARoot superclass removeSubclass: classThatIsARoot.	"just in case"
		(Smalltalk at: classThatIsARoot name) becomeForward: classThatIsARoot.
		catInstaller value.
		^ classThatIsARoot superclass addSubclass: classThatIsARoot].
	self error: 'Name already in use by a non-class: ', classThatIsARoot name.

]

{ #category : #fileIn }
ImageSegment >> dependentsCancel: aProject [
	"Erase the place we temporarily held the dependents of things in this project.  So we don't carry them around forever."

	aProject projectParameters removeKey: #GlobalDependentsInProject ifAbsent: []
]

{ #category : #fileIn }
ImageSegment >> dependentsRestore: aProject [
	"Retrieve the list of dependents from the exporting system, hook them up, and erase the place we stored them."

	| dict |
	dict := aProject projectParameterAt: #GlobalDependentsInProject.
	dict ifNil: [^ self].
	dict associationsDo: [:assoc |
		assoc value do: [:dd | assoc key addDependent: dd]].

	self dependentsCancel: aProject.
]

{ #category : #'fileIn/Out' }
ImageSegment >> endianness [
	"Return which endian kind the incoming segment came from"

	segment class isBits ifFalse:
		["Hope that primitive 98 did the right thing - anyway, we lost information about endianness, so pretend we share the image's endianness."
		^Smalltalk endianness].
	^(segment first bitShift: -24) asCharacter == $d ifTrue: [#big] ifFalse: [#little]
]

{ #category : #testing }
ImageSegment >> errorWrongState [

	^ self error: 'wrong state'
]

{ #category : #fileIn }
ImageSegment >> fixCapitalizationOfSymbols [
	"MultiString>>capitalized was not implemented 
correctly. 
	Fix eventual accessors and mutators here."
	| sym ms |
	1 to: outPointers size do:[:i|
		sym := outPointers at: i.
		(sym class == WideSymbol and:[sym size > 3]) ifTrue:[
			((sym beginsWith: 'get')
				and:[(sym at: 4) asInteger < 256
				and:[(sym at: 4) isLowercase]]) ifTrue:[
					ms := sym asString.
					ms at: 4 put: (ms at: 4) asUppercase.
					ms := ms asSymbol.
					sym becomeForward: ms.
			].
			((sym beginsWith: 'set')
				and:[(sym at: 4) asInteger < 256
				and:[(sym at: 4) isLowercase
				and:[sym last = $:
				and:[(sym occurrencesOf: $:) = 1]]]]) ifTrue:[
					ms := sym asString.
					ms at: 4 put: (ms at: 4) asUppercase.
					ms := ms asSymbol.
					sym becomeForward: ms.
				].
			outPointers at: i put: sym.
		].
	].
]

{ #category : #testing }
ImageSegment >> forFile: aFileName outPointers: outPointerArray [
	"An accessor for testing to set up a new image segment to be in a state to load from aFileName.  After this send install to load."
	fileName := aFileName.
	state := #onFile.
	outPointers := outPointerArray
]

{ #category : #'read/write segment' }
ImageSegment >> install [
	"This operation retrieves the segment if necessary from file storage, installs it in memory, and replaces (using become:) all the root stubs with the reconstructed roots of the segment."

	| allObjectsInSegment newRoots |
	(state = #active) | (state = #imported) ifFalse: [self errorWrongState].
	allObjectsInSegment := self loadSegmentFrom: segment outPointers: outPointers.
	newRoots := allObjectsInSegment first.
	self checkAndReportLoadError.
	(state = #imported "just came in from exported file" or: [arrayOfRoots isNil "testing..."])
		ifTrue: [arrayOfRoots := newRoots]
		ifFalse: [arrayOfRoots elementsForwardIdentityTo: newRoots].
	state := #inactive.
	Beeper beepPrimitive
]

{ #category : #'read/write segment' }
ImageSegment >> loadSegmentFrom: aSegment outPointers: theOutPointers [
	"Attempt to load the segment into memory (reify the objects in segment
	 as real objects), using outPointers to bind references to objects not in the
	 segment.  Answer a collection of all the objects in the segment."

	| segmentFormat |
	(state == #imported or: [state == #active]) ifTrue:
		[segmentFormat := self segmentFormatFrom: aSegment first.
		 (#(6502 6504) includes: segmentFormat) ifTrue:
			[LegacyImageSegment adoptInstance: self.
			 ^self loadSegmentFrom: aSegment outPointers: theOutPointers].
		 segmentFormat = Smalltalk imageFormatVersion ifTrue:
			[NativeImageSegment adoptInstance: self.
			 ^self loadSegmentFrom: aSegment outPointers: theOutPointers].
		 self error: 'no handling for format ', segmentFormat asString. ' in a ', Smalltalk imageFormatVersion asString, ' image.'].
	self subclassResponsibility
]

{ #category : #'read/write segment' }
ImageSegment >> localName [
	| segs ind sep |
	"Return the current file name for this segment, a local name in the segments directory."

	fileName ifNil: [^ nil].
	"^ fileName"	

	"The following is for backward compatibility.  Remove this part after June 2000.
	Check if the fileName is a full path, and make it local.  Regardless of current or previous file system delimiter."

	segs := self class folder copyLast: 4.  ":=segs"
	ind := 1.
	[ind := fileName findString: segs startingAt: ind+1 caseSensitive: false.
		ind = 0 ifTrue: [^ fileName].
		sep := fileName at: ind + (segs size).
		sep isAlphaNumeric ] whileTrue.		"sep is letter or digit, not a separator"

	^ fileName := fileName copyFrom: ind+(segs size)+1 "delimiter" to: fileName size
]

{ #category : #fileIn }
ImageSegment >> rehashDictionaries: aCollection [ 
	1
		to: aCollection size
		do: [:i | 
			(aCollection at: i) rehash ]
]

{ #category : #fileIn }
ImageSegment >> reshapeClasses: mapFakeClassesToReal refStream: smartRefStream [

	| bads allVarMaps partials in out perfect |

	self flag: #bobconv.	

	partials := OrderedCollection new.
	bads := OrderedCollection new.
	allVarMaps := IdentityDictionary new.
	mapFakeClassesToReal keysAndValuesDo: [ :aFakeClass :theRealClass |
		aFakeClass allInstances do: [ :misShapen |
			perfect := smartRefStream convert1: misShapen to: theRealClass allVarMaps: allVarMaps.
			bads
				detect: [ :x | x == misShapen]
				ifNone: [
					bads add: misShapen.
					partials add: perfect
				].
		].
	].
	bads isEmpty ifFalse: [
		bads asArray elementsForwardIdentityTo: partials asArray
	].

	in := OrderedCollection new.
	out := OrderedCollection new.
	partials do: [ :each |
		perfect := smartRefStream convert2: each allVarMaps: allVarMaps.
		in
			detect: [ :x | x == each]
			ifNone: [
				in add: each.
				out add: perfect
			]
	].
	in isEmpty ifFalse: [
		in asArray elementsForwardIdentityTo: out asArray
	].

]

{ #category : #'fileIn/Out' }
ImageSegment >> restoreEndianness [
	^self restoreEndianness: self endianness ~~ Smalltalk endianness
]

{ #category : #fileIn }
ImageSegment >> restoreEndianness: endiannessHasToBeFixed [
	"If endiannessHasToBeFixed, then fix endianness (byte order) of any objects not already fixed.  Do this by discovering classes that need a startUp message sent to each instance, and sending it.
	I have just been brought in and converted to live objects.  Find all Sets and Dictionaries in the newly created objects and rehash them.  Segment is near then end of memory, since is was newly brought in (and a new object created for it).
	Also, collect all classes of receivers of blocks which refer to instance variables.  Return them.  Caller will check if they have been reshaped."

	| sets receiverClasses noStartUpNeeded startUps cls msg |
	sets := OrderedCollection new.
		"have to collect them, because Dictionary makes a copy, and that winds up at the end of memory and gets rehashed and makes another one."
	receiverClasses := IdentitySet new.
	noStartUpNeeded := IdentitySet new.	"classes that don't have a per-instance startUp message"
	startUps := IdentityDictionary new.	"class -> MessageSend of a startUp message"
	self allObjectsDo: [:object |
		object isInMemory ifTrue: [
			(object isKindOf: HashedCollection) ifTrue: [sets add: object].
			(object isContext and: [object hasInstVarRef]) ifTrue: [
				receiverClasses add: (object objectClass: object receiver) class].
			(noStartUpNeeded includes: object class) ifFalse: [
				cls := object class.
				(msg := startUps at: cls ifAbsent: [nil]) ifNil: [
					msg := cls startUpFrom: endiannessHasToBeFixed.	"a Message, if we need to swap bytes this time"
					msg ifNil: [noStartUpNeeded add: cls]
						ifNotNil: [startUps at: cls put: msg]].
				msg ifNotNil: [msg sentTo: object]]]].
	self rehashDictionaries: sets. "our purpose"
	^ receiverClasses	"our secondary job"
]

{ #category : #'fileIn/Out' }
ImageSegment >> scanFrom: aStream [
	"Move source code from a fileIn to the changes file for classes in an ImageSegment.  Do not compile the methods.  They already came in via the image segment.  After the ImageSegment in the file, !ImageSegment new! captures control, and scanFrom: is called."
	| val chunk |

	[aStream atEnd] whileFalse: 
		[aStream skipSeparators.
		val := (aStream peekFor: $!)
			ifTrue: ["Move (aStream nextChunk), find the method or class 
						comment, and install the file location bytes"
					(self class compiler
						source: aStream nextChunk;
						logged: false;
						evaluate)
						scanFromNoCompile: aStream forSegment: self]
			ifFalse: [chunk := aStream nextChunk.
					aStream checkForPreamble: chunk.
					self class compiler
						source: chunk;
						logged: true;
						evaluate ].
		aStream skipStyleChunk].
	"regular fileIn will close the file"
	^ val
]

{ #category : #'fileIn/Out' }
ImageSegment >> scanFrom: aStream environment: anEnvironment [
	^ self scanFrom: aStream
]

{ #category : #private }
ImageSegment >> segmentFormatFrom: a32BitWord [
	"The first two words of a segment array contain the image format version of the system upon which the segment was generated, along with a top byte that is either $d or $s (from the 'does' in #doesNotUnderstand:).  But this may be encoded either in big-endian or little-endian format.  Since endianness may or may not have been changed, determining what the segment format is takes care."
	| msc lsc |
	msc := Character value: ((a32BitWord bitShift: -24) bitAnd: 255).
	lsc := Character value: (a32BitWord bitAnd: 255).
	(('ds' includes: msc)
	 and: ['ds' includes: lsc]) ifTrue:
		[self error: 'ambiguous segment format'].
	('ds' includes: msc) ifTrue:
		[^a32BitWord bitAnd: 16rFFFFFF].
	^((a32BitWord bitShift: -24) bitAnd: 16rFF)
	+ ((a32BitWord bitShift: -8) bitAnd: 16rFF00)
	+ ((a32BitWord bitShift: 8) bitAnd: 16rFF0000)
]
