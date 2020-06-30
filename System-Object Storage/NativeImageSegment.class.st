"
NativeImageSegment is used to save and restore projects.  It uses
one primitive to create a segment (a WordArray) whose contents
are the objects in the project in the same format as they appear in
the VM's heap.  It uses another primitive to convert a segment back
into objects.
"
Class {
	#name : #NativeImageSegment,
	#superclass : #ImageSegment,
	#classVars : [
		'BiggestFileNumber'
	],
	#category : #'System-Object Storage'
}

{ #category : #testing }
NativeImageSegment class >> activeClasses [   "NativeImageSegment activeClasses"
	"Restore all remaining MD faults and return the active classes"

	| unused active |
	unused := OrderedCollection new.
	active := OrderedCollection new.
	Smalltalk allClasses do:
		[:c | (c instVarNamed: 'methodDict') 
			ifNil: [unused addLast: c]
			ifNotNil: [active addLast: c]].
	unused do: [:c | c recoverFromMDFault].
	^ active
]

{ #category : #testing }
NativeImageSegment class >> activeClassesByCategory [   "NativeImageSegment activeClassesByCategory"
	"Return a dictionary of active classes by system category.
	Useful for finding kernel categories to minimize swapping."

	| active dict |
	active := self activeClasses.
	dict := Dictionary new.
	active do:
		[:c | | cat list | cat := c category.
		list := dict at: cat ifAbsent: [Array new].
		dict at: cat put: (list copyWith: c)].
	^ dict
"
	NativeImageSegment discoverActiveClasses  <-- do it
		-- do something typical --
	NativeImageSegment activeClassesByCategory  <-- inspect it
"
]

{ #category : #accessing }
NativeImageSegment class >> compressedFileExtension [
	^'sqz'
]

{ #category : #testing }
NativeImageSegment class >> discoverActiveClasses [   "NativeImageSegment discoverActiveClasses" 
	"Run this method, do a few things, maybe save and resume the image.
	This will leave unused classes with MDFaults.
	You MUST follow this soon by activeClasses, or by swapOutInactiveClasses."

	"NOTE:  discoverActiveClasses uses Squeak's ability to detect and recover from faults due to a nil method dictionary.  It staches the method dict in with the organization during the time when discovery is in progress (Gag me with a spoon).  This is why the faults need to be cleared promptly before resuming normal work with the system.  It is also important that classes *do not* refer directly to their method dictionary, but only via the accessor message."
	
	Smalltalk allClasses do:
		[:c | | ok | ok := true.
		#(Array Object Class Message MethodDictionary) do:
			[:n | ((Smalltalk at: n) == c or:
				[(Smalltalk at: n) inheritsFrom: c]) ifTrue: [ok := false]].
		ok ifTrue: [c induceMDFault]].
"
	NativeImageSegment discoverActiveClasses.
		-- do something typical --
	PopUpMenu notify: NativeImageSegment activeClasses size printString , ' classes were active out of ' ,
			Smalltalk allClasses size printString.
"
]

{ #category : #accessing }
NativeImageSegment class >> fileExtension [
	^'extSeg'
]

{ #category : #'fileIn/Out' }
NativeImageSegment class >> segmentDirectory [
	"Return a directory object for the folder of segments.
	Create such a folder if none exists."
	^ (FileLocator imageDirectory / self folder) ensureCreateDirectory
]

{ #category : #'fileIn/Out' }
NativeImageSegment class >> shutDown [
	"Delete segment files that can't be used after this image is saved."

	"This is Optional.  
(1) How tell if saving image now?  Only do if is.
(2) NativeImageSegmentRootStub allInstancesDo: 
	If more than one file, delete all but one we are using now.
	Leave files with not stubs (could be out in a segment)
	Must forbid two projects from having the same name!
(3) all Projects do:
	If project is in, delete all files with its name.
"
	
]

{ #category : #'fileIn/Out' }
NativeImageSegment class >> uniqueFileNameFor: segName [
	"Choose a unique file name for the segment with this name."
	| segDir fileName listOfFiles |
	segDir := self segmentDirectory.
	listOfFiles := segDir fileNames.
	BiggestFileNumber ifNil: [BiggestFileNumber := 1].
	BiggestFileNumber > 99 ifTrue: [BiggestFileNumber := 1].	"wrap"
	[fileName := segName, BiggestFileNumber printString, '.seg'.
	 (listOfFiles includes: fileName)] whileTrue: [
		BiggestFileNumber := BiggestFileNumber + 1].	"force a unique file name"
	^ fileName
]

{ #category : #'compact classes' }
NativeImageSegment >> aComment [
	"Spur does not use compact classes, so an effort has been made to excise their use from the code.  The previous comment was:

	Compact classes are a potential problem because a pointer to the class would not ordinarily show up in the outPointers.  We add the classes of all compact classes to outPointers, both for local and export segments.
	Compact classes are never allowed as roots.  No compact class may be in an Environment that is written out to disk.  (In local segments, the compact classes array should never have an ImageSegmentRootStub in it.  For export, fileIn the class first, then load a segment with instances of it.  The fileIn code can be pasted onto the front of the .extSeg file) 
	For local segments, a class may become compact while its instances are out on the disk.  Or it may become un-compact.  A compact class may change shape while some of its instances are on disk.  All three cases go through (ClassDescription updateInstancesFrom:).  If it can't rule out an instance being in the segment, it reads it in to fix the instances.  
	See Behavior.becomeCompact for the rules on Compact classes.  Indexes may not be reused.  This is so that an incoming export segment has its index available.  (Changes may be needed in the way indexes are assigned.)
	For export segments, a compact class may have a different shape.  The normal class reshape mechanism will catch this.  During the installation of the segment, objects will have the wrong version of their class momentarily.  We will change them back before we get caught.
	For export segments, the last two items in outPointers are the number 1717 and an array of the compact classes used in this segment.  (The classes in the array are converted from DiskProxies by SmartRefStream.)  If that class is not compact in the new image, the instances are recopied."
]

{ #category : #'read/write segment' }
NativeImageSegment >> copyFromRoots: aRootArray sizeHint: segSizeHint [
	"Copy a tree of objects into a WordArray segment.  The copied objects in the segment are not in the normal Squeak space.  If this method yields a very small segment, it is because objects just below the roots are pointed at from the outside.  (See findRogueRootsImSeg: for a *destructive* diagnostic of who is pointing in.)
	Caller must hold onto Symbols.
	To go faster, make sure objects are not repeated in aRootArray and other method directly, with true."

	self copyFromRoots: aRootArray sizeHint: segSizeHint areUnique: false
]

{ #category : #'read/write segment' }
NativeImageSegment >> copyFromRoots: aRootArray sizeHint: segSizeHint areUnique: areUnique [
	"Copy a tree of objects into a WordArray segment.  The copied objects in the segment are not in the normal Squeak space.  
	[1] For exporting a project.  Objects were enumerated by ReferenceStream and aRootArray has them all.
	[2] For exporting some classes.  See copyFromRootsForExport:. (Caller must hold Symbols, or they will not get registered in the target system.)
	[3] For 'local segments'.  outPointers are kept in the image.
	If this method yields a very small segment, it is because objects just below the roots are pointed at from the outside.  (See findRogueRootsImSeg: for a *destructive* diagnostic of who is pointing in.)"
	| segmentWordArray outPointerArray segSize rootSet uniqueRoots |
	aRootArray ifNil: [self errorWrongState].
	uniqueRoots := areUnique 
		ifTrue: [aRootArray]
		ifFalse: [rootSet := IdentitySet new: aRootArray size * 3.
			uniqueRoots := OrderedCollection new.
			1 to: aRootArray size do: [:ii |	"Don't include any roots twice"
				(rootSet includes: (aRootArray at: ii)) 
					ifFalse: [
						uniqueRoots addLast: (aRootArray at: ii).
						rootSet add: (aRootArray at: ii)]
					ifTrue: [userRootCnt ifNotNil: ["adjust the count"
								ii <= userRootCnt ifTrue: [userRootCnt := userRootCnt - 1]]]].
			uniqueRoots].
	arrayOfRoots := uniqueRoots asArray.
	rootSet := uniqueRoots := nil.	"be clean"
	userRootCnt ifNil: [userRootCnt := arrayOfRoots size].
	outPointers := nil.	"may have used this instance before"
	segSize := segSizeHint > 0 ifTrue: [segSizeHint *3 //2] ifFalse: [50000].

	["Guess a reasonable segment size"
	segmentWordArray := WordArrayForSegment new: segSize.
	outPointerArray := [Array new: segSize // 20] ifError: [
		state := #tooBig.  ^ self].
	"Smalltalk garbageCollect."
	(self storeSegmentFor: arrayOfRoots
					into: segmentWordArray
					outPointers: outPointerArray) == nil]
		whileTrue:
			["Double the segment size and try again"
			segmentWordArray := outPointerArray := nil.
			segSize := segSize * 2].
	segment := segmentWordArray.
	outPointers := outPointerArray.
	state := #activeCopy
]

{ #category : #'read/write segment' }
NativeImageSegment >> copyFromRootsForExport: rootArray [ 
	"When possible, use copySmartRootsExport:.  This way may not copy a complete tree of objects.  Add to roots: all of the methods pointed to from the outside by blocks."
	| newRoots segSize symbolHolder |
	arrayOfRoots := rootArray.
	"self halt."
	symbolHolder := Symbol allSymbols.	"Hold onto Symbols with strong pointers, 
		so they will be in outPointers"
	"Creation of the segment happens here"
	self copyFromRoots: arrayOfRoots sizeHint: 0.
	segSize := segment size.
	[(newRoots := self rootsIncludingBlockMethods) == nil] whileFalse:
		[arrayOfRoots := newRoots.
		self copyFromRoots: arrayOfRoots sizeHint: segSize].
		"with methods pointed at from outside"
	[(newRoots := self rootsIncludingBlocks) == nil] whileFalse:
		[arrayOfRoots := newRoots.
		self copyFromRoots: arrayOfRoots sizeHint: segSize].
		"with methods, blocks from outPointers"
	"Zap sender of a homeContext. Can't send live stacks out." "Why not? eem 7/3/2017 15:31"
	1 to: outPointers size do: [:ii | | outPointer |
		outPointer := outPointers at: ii.
		(outPointer isBlock
		 or: [outPointer isContext]) ifTrue: [outPointers at: ii put: nil]].
	symbolHolder size "Keep reference to symbolHolder until the last"
]

{ #category : #'read/write segment' }
NativeImageSegment >> copySmartRootsExport: rootArray [ 
	"Use SmartRefStream to find the object.  Make them all roots.  Create the segment in memory.  Project should be in first five objects in rootArray."
	| newRoots segSize symbolHolder replacements naughtyBlocks allClasses sizeHint proj dummy world |

	"self halt."
	world := UIManager default currentWorld.
	symbolHolder := Symbol allSymbols.	"Hold onto Symbols with strong pointers, 
		so they will be in outPointers"

	dummy := ReferenceStream on: (DummyStream on: nil).
		"Write to a fake Stream, not a file"
	"Collect all objects"
	dummy insideASegment: true.	"So Uniclasses will be traced"
	dummy rootObject: rootArray.	"inform him about the root"
	dummy nextPut: rootArray.
	(proj :=dummy project) ifNotNil: [self dependentsSave: dummy].
	"refs := dummy references."
	arrayOfRoots := self smartFillRoots: dummy.	"guaranteed none repeat"
	replacements := dummy blockers.
	dummy project "recompute it" ifNil: [self error: 'lost the project!'].
	dummy project class == DiskProxy ifTrue: [self error: 'saving the wrong project'].
	dummy := nil.	"Allow dummy to be GC'ed below (bytesLeft)."
	naughtyBlocks := arrayOfRoots select: [ :each |
		each isContext and: [each hasInstVarRef]].

	"since the caller switched ActiveWorld, put the real one back temporarily"
	naughtyBlocks isEmpty ifFalse: [
		world becomeActiveDuring: [world firstHand becomeActiveDuring: [ | goodToGo |
			goodToGo := (UIManager default
				chooseFrom: #('keep going' 'stop and take a look')
				title:
'Some block(s) which reference instance variables 
are included in this segment. These may fail when
the segment is loaded if the class has been reshaped.
What would you like to do?') = 1.
			goodToGo ifFalse: [
				naughtyBlocks inspect.
				self error: 'Here are the bad blocks'].
		]].
	].
	"Creation of the segment happens here"

	"try using one-quarter of memory min: four megs to publish (will get bumped up later if needed)"
	sizeHint := (Smalltalk bytesLeft // 4 // 4) min: 1024*1024.
	self copyFromRoots: arrayOfRoots sizeHint: sizeHint areUnique: true.
	segSize := segment size.
	[(newRoots := self rootsIncludingBlockMethods) == nil] whileFalse:
		[arrayOfRoots := newRoots.
		self copyFromRoots: arrayOfRoots sizeHint: segSize areUnique: true].
		"with methods pointed at from outside"
	[(newRoots := self rootsIncludingBlocks) == nil] whileFalse:
		[arrayOfRoots := newRoots.
		self copyFromRoots: arrayOfRoots sizeHint: segSize areUnique: true].
		"with methods, blocks from outPointers"
	1 to: outPointers size do: [:ii | | outPointer |
		outPointer := outPointers at: ii.
		(outPointer isBlock
		 or: [outPointer isContext]) ifTrue: [outPointers at: ii put: nil].
		"substitute new object in outPointers"
		(replacements includesKey: outPointer) ifTrue:
			[outPointers at: ii put: (replacements at: outPointer)]].
	proj ifNotNil: [self dependentsCancel: proj].
	symbolHolder. "hold onto symbolHolder until the last."
]

{ #category : #statistics }
NativeImageSegment >> copyStatisticsDictionaryWithClassNames: aDictionary [
	| d |
	d := aDictionary copyEmpty.
	aDictionary keysAndValuesDo:
		[:classIndex :value|
		 d
			at: ((classIndex anyMask: 16r200000) "TopHashBit = 16r200000, => in out pointers"
					ifTrue: [(outPointers at: classIndex - 16r200000 + 1) name]
					ifFalse: ['InSegmentClass', classIndex asString])
			put: value].
	^d
]

{ #category : #testing }
NativeImageSegment >> deepCopyTest: aRootArray [
	"NativeImageSegment new deepCopyTest: Morph withAllSubclasses asArray"
	"Project allInstances do:
		[:p | p == Project current ifFalse:
			[Transcript cr; cr; nextPutAll: p name.
			NativeImageSegment new deepCopyTest: (Array with: p)]]."
	| t1 t2 copy |
	t1 := Time millisecondsToRun: [self copyFromRoots: aRootArray sizeHint: 0].
	t2 := Time millisecondsToRun: [copy := self segmentCopy].
	Transcript cr; print: segment size * 4; nextPutAll: ' bytes stored with ';
		print: outPointers size; show: ' outpointers in '; print: t1; show: 'ms.'.
	Transcript cr; nextPutAll: 'Reconstructed in '; print: t2; show: 'ms.'.
	^ copy
"
Smalltalk allClasses do:
	[:m | NativeImageSegment new deepCopyTest: (Array with: m with: m class)]
"
]

{ #category : #'read/write segment' }
NativeImageSegment >> dependentsSave: dummy [
	"Object that have dependents are supposed to be instances of subclasses of Model.  But, class Objects still provides 'Global Dependents', and some people still use them.  When both the model and the dependent are in a project that is being saved, remember them, so we can hook them up when this project is loaded in."

	| dict proj |
	proj := dummy project.
	dict := Dictionary new.
	DependentsFields associationsDo: [:assoc | | list |
		(dummy references includesKey: assoc key) ifTrue: [
			list := assoc value select: [:dd | dummy references includesKey: dd].
			list size > 0 ifTrue: [dict at: assoc key put: list]]].

	dict size > 0 ifTrue: [
		proj projectParameterAt: #GlobalDependentsInProject put: dict].
]

{ #category : #statistics }
NativeImageSegment >> doSpaceAnalysis [
	"Capture statistics about the IS and print the number of instances per class and space usage"
	| is64Bit index instCount instSpace |
	state == #activeCopy ifFalse:[self errorWrongState].
	instCount := Dictionary new.
	instSpace := Dictionary new.
	is64Bit := ((segment at: 1) bitAnd: 16rFFFFFF) >= 68000.
	index := 3. 	"skip version word"
	"The Spur image format (in little endian format) is (num bits:fieldName(s)))
	 msb:	| 8: numSlots		| (on a byte boundary)
			| 2 bits				|	(msb,lsb = {isMarked,?})
			| 22: identityHash	| (on a word boundary)
			| 3 bits				|	(msb <-> lsb = {isGrey,isPinned,isRemembered}
			| 5: format			| (on a byte boundary)
			| 2 bits				|	(msb,lsb = {isImmutable,?})
			| 22: classIndex		| (on a word boundary) : LSB"
	[index > segment size] whileFalse:
		[| hiWord loWord numSlots bytes classIndex |
		 loWord := segment at: index.
		 hiWord := segment at: index + 1.
		 numSlots := hiWord bitShift: -24.
		 numSlots = 255
			ifTrue: "word is an overflow header word.  Slot count is in the least significant 56 bits."
				[numSlots := hiWord = 0
								ifTrue: [loWord]
								ifFalse: [(hiWord bitShift: 32) + loWord bitAnd: 16rFFFFFFFFFFFFFF].
				 loWord := segment at: index + 2.
				 hiWord := segment at: index + 3.
				 bytes := 16] "two word header"
			ifFalse:
				[bytes := 8]. "one word header"
		 bytes := bytes + (8 * is64Bit "objects are a multiple of 8 bytes in length, with at leats one slot"
								ifTrue: [numSlots max: 1]
								ifFalse: [(numSlots max: 1) + 1 // 2]).
		 classIndex := loWord bitAnd: 16r3FFFFF.
		 (index > 3 or: [classIndex ~~ 33]) ifTrue: "Don't count the initial arrayOfRoots"
			 [instCount at: classIndex put: (instCount at: classIndex ifAbsent:[0]) + 1.
			  instSpace at: classIndex put: (instSpace at: classIndex ifAbsent:[0]) + bytes].
		 index := index + (bytes / 4)].
	^{instCount. instSpace} collect: [:dict| self copyStatisticsDictionaryWithClassNames: dict]
]

{ #category : #'read/write segment' }
NativeImageSegment >> extract [
	"This operation replaces (using become:) all the original roots of a segment with segmentRootStubs.  Thus the original objects will be reclaimed, and the root stubs will remain to bring the segment back in if it is needed."

	Cursor write showWhile: [
		state = #inactive ifTrue: [self copyFromRoots: arrayOfRoots sizeHint: 0].
		state = #activeCopy ifFalse: [self errorWrongState].
		arrayOfRoots elementsForwardIdentityTo:
			(arrayOfRoots collect: [:r | r rootStubInImageSegment: self]).
		state := #active].
]

{ #category : #'read/write segment' }
NativeImageSegment >> extractThenInstall [
	"For testing only"

	| allObjectsInSegment newRoots |
	state = #activeCopy ifFalse: [self errorWrongState].
	arrayOfRoots elementsForwardIdentityTo:
		(arrayOfRoots collect: [:r | r rootStubInImageSegment: self]).
	state := #active.
	allObjectsInSegment := self loadSegmentFrom: segment outPointers: outPointers.
	newRoots := allObjectsInSegment first.
	state := #inactive.
	arrayOfRoots elementsForwardIdentityTo: newRoots.
]

{ #category : #testing }
NativeImageSegment >> findInOut: anArray [
	"Take an array of references to a morph, and try to classify them:  in the segment, in outPointers, or other."

String streamContents: [:strm |
	anArray withIndexDo: [:obj :ind |
		strm cr; nextPutAll: obj printString; space.

		]].
]

{ #category : #testing }
NativeImageSegment >> findOwnerMap: morphs [
	| st |
	"Construct a string that has a printout of the owner chain for every morph in the list.  Need it as a string so not hold onto them."

st := ''.
morphs do: [:mm |
	(st includesSubstring: mm printString) ifFalse: [
		st := st, '
', mm allOwners printString]].
Smalltalk at: #Owners put: st.
]

{ #category : #testing }
NativeImageSegment >> findOwnersOutPtrs [

| ow ff |
ow := Smalltalk at: #Owners ifAbsent: [^ self].
ow ifNil: [^ self].
outPointers do: [:oo | 
	oo isMorph ifTrue: [
		ow := ow copyReplaceAll: oo printString with: oo printString, '[<<<- Pointed at]']].
ff := FileStream fileNamed: 'Owners log'.
ff nextPutAll: ow; close.
Smalltalk at: #Owners put: ow.
ff edit.
]

{ #category : #testing }
NativeImageSegment >> findRogueRootsRefStrm: rootArray [ 
	"This is a tool to track down unwanted pointers into the segment.  If we don't deal with these pointers, the segment turns out much smaller than it should.  These pointers keep a subtree of objects out of the segment.
1) assemble all objects that should be in the segment by using SmartReference Stream and a dummyReference Stream.  Put in a Set.
2) Remove the roots from this list.  Ask for senders of each.  Of the senders, forget the ones that are in the segment already.  Keep others.  The list is now all the 'incorrect' pointers into the segment."

	| goodInSeg inSeg pointIn dummy |
	dummy := ReferenceStream on: (DummyStream on: nil).
	"Write to a fake Stream, not a file"
	rootArray do: 
			[:root | 
			dummy rootObject: root.	"inform him about the root"
			dummy nextPut: root].
	inSeg := dummy references keys asSet.
	dummy := nil.
	Smalltalk garbageCollect.	"dump refs dictionary"
	rootArray do: [:each | inSeg remove: each ifAbsent: []].
	"want them to be pointed at from outside"
	pointIn := IdentitySet new: 500.
	goodInSeg := IdentitySet new: 2000.
	inSeg do: 
			[:obj | | ok | 
			ok := obj class isPointers.
			obj class == Color ifTrue: [ok := false].
			obj class == Array ifTrue: [obj size = 0 ifTrue: [ok := false]].
			"shared #() in submorphs of all Morphs"
			ok ifTrue: [goodInSeg add: obj]].
	goodInSeg 
		do: [:ob | pointIn addAll: (ob pointersToExcept: #())].
	inSeg do: [:each | pointIn remove: each ifAbsent: []].
	rootArray do: [:each | pointIn remove: each ifAbsent: []].
	pointIn remove: inSeg array ifAbsent: [].
	pointIn remove: goodInSeg array ifAbsent: [].
	pointIn remove: pointIn array ifAbsent: [].
	self halt: 'Examine local variables pointIn and inSeg'.
	^pointIn
]

{ #category : #'read/write segment' }
NativeImageSegment >> findStacks [
	"Return an array of all the StackMorphs in this project."
	| guys stacks |
	guys := IdentitySet new.
	Smalltalk at: #StackMorph ifPresent:[:aClass|
		guys addAll: aClass withAllSubclasses.
	].
	stacks := OrderedCollection new.
	arrayOfRoots do: [:obj |
		(guys includes: obj class) ifTrue: [stacks add: obj]].
	^ stacks
]

{ #category : #testing }
NativeImageSegment >> isOnFile [
	^ state == #onFile
]

{ #category : #'read/write segment primitives' }
NativeImageSegment >> loadSegmentFrom: segmentWordArray outPointers: outPointerArray [
	"Load segmentWordArray into the memory.  Adapt the primitive to the new API, which is to answer the array of loaded objects, the first of which should be the array of roots.  The primitive will install a binary image segment and return as its value the array
	 of roots of the tree of objects represented.  Upon successful completion, the
	 wordArray will have been becomed into anArray of the loaded objects.  So simply answer the segmentWordArray which will have becommed."

	| segmentFormat |
	segmentFormat := self segmentFormatFrom: segmentWordArray first.
	segmentFormat = Smalltalk imageFormatVersion ifTrue:
		[^(self primitiveLoadSegmentFrom: segmentWordArray outPointers: outPointerArray)
			ifNil: [self error: 'segment load failed']
			ifNotNil: [segmentWordArray]].
	segmentFormat >= 68000
		ifTrue:
			[Smalltalk wordSize = 4 ifTrue:
				[^(Spur64BitImageSegmentLoader new loadSegmentFrom: segmentWordArray outPointers: outPointerArray)]]
		ifFalse:
			[Smalltalk wordSize = 8 ifTrue:
				[^(Spur32BitImageSegmentLoader new loadSegmentFrom: segmentWordArray outPointers: outPointerArray)]].
	self error: 'segment version unrecognized'
]

{ #category : #access }
NativeImageSegment >> originalRoots [
	"Return only the roots that the user submitted, not the ones we had to add."

	userRootCnt ifNil: [^ arrayOfRoots].
	^ arrayOfRoots copyFrom: 1 to: userRootCnt
]

{ #category : #access }
NativeImageSegment >> outPointers [
	^ outPointers
]

{ #category : #'fileIn/Out' }
NativeImageSegment >> prepareToBeSaved [
	"Prepare objects in outPointers to be written on the disk.  They must be able to match up with existing objects in their new system.  outPointers is already a copy.
	Classes are already converted to a DiskProxy.  
	Associations in outPointers:
1) in Smalltalk.
2) in a classPool.
3) in a shared pool.
4) A pool dict pointed at directly"

| left myClasses outIndexes |
self flag: #environments.
myClasses := Set new.
arrayOfRoots do: [:aRoot | aRoot class class == Metaclass ifTrue: [myClasses add: aRoot]].
outIndexes := IdentityDictionary new.
outPointers withIndexDo: [:anOut :ind | | key | 
	anOut isVariableBinding ifTrue: [
		(myClasses includes: anOut value)
			ifFalse: [outIndexes at: anOut put: ind]
			ifTrue: [(Smalltalk globals associationAt: anOut key ifAbsent: [3]) == anOut 
				ifTrue: [outPointers at: ind put: 
					(DiskProxy global: #Smalltalk selector: #associationDeclareAt: 
						args: (Array with: anOut key))]
				ifFalse: [outIndexes at: anOut put: ind]
				]].
	(anOut isKindOf: Dictionary) ifTrue: ["Pools pointed at directly"
		(key := Smalltalk globals keyAtIdentityValue: anOut ifAbsent: [nil]) ifNotNil: [
			outPointers at: ind put: 
				(DiskProxy global: key selector: #yourself args: #())]].
	anOut isMorph ifTrue: [outPointers at: ind put: 
		(StringMorph contents: anOut printString, ' that was not counted')]
	].
left := outIndexes keys asSet.
left size > 0 ifTrue: ["Globals"
	(left copy) do: [:assoc |	"stay stable while delete items"
		(Smalltalk globals associationAt: assoc key ifAbsent: [3]) == assoc ifTrue: [
			outPointers at: (outIndexes at: assoc) put: 
				(DiskProxy global: #Smalltalk selector: #associationAt: 
					args: (Array with: assoc key)).
			left remove: assoc]]].
left size > 0 ifTrue: ["Class variables"
	Smalltalk allClassesDo: [:cls | cls classPool size > 0 ifTrue: [
		(left copy) do: [:assoc |	"stay stable while delete items"
			(cls classPool associationAt: assoc key ifAbsent: [3]) == assoc ifTrue: [
				outPointers at: (outIndexes at: assoc) put: 
					(DiskProxy new global: cls name
						preSelector: #classPool
						selector: #associationAt: 
						args: (Array with: assoc key)).
				left remove: assoc]]]]].
left size > 0 ifTrue: ["Pool variables"
	Smalltalk globals associationsDo: [:poolAssoc | | pool |
		poolAssoc value class == Dictionary ifTrue: ["a pool"
			pool := poolAssoc value.
			(left copy) do: [:assoc |	"stay stable while delete items"
				(pool associationAt: assoc key ifAbsent: [3]) == assoc ifTrue: [
					outPointers at: (outIndexes at: assoc) put: 
						(DiskProxy global: poolAssoc key selector: #associationAt: 
							args: (Array with: assoc key)).
					left remove: assoc]]]]].
left size > 0 ifTrue: [
	"If points to class in arrayOfRoots, must deal with it separately"
	"OK to have obsolete associations that just get moved to the new system"
	self inform: 'extra associations'.
	left inspect].
]

{ #category : #'read/write segment primitives' }
NativeImageSegment >> primitiveLoadSegmentFrom: segmentWordArray outPointers: outPointerArray [
	"This primitive will install a binary image segment and return as its value the array
	 of roots of the tree of objects represented.  Upon successful completion, the
	 wordArray will have been becomed into anArray of the loaded objects.  If this
	 primitive should fail, it will have destroyed the contents of the segment wordArray."

	<primitive: 99 error: ec>	"successful completion returns the array of roots"
	^nil								"failure returns nil"
]

{ #category : #statistics }
NativeImageSegment >> printSpaceAnalysisOn: aStream [
	"Capture statistics about the IS and print the number of instances per class and space usage"
	| instCount instSpace sorted sum1 sum2 |
	instCount := self doSpaceAnalysis.
	instSpace := instCount last.
	instCount := instCount first.
	sorted := SortedCollection sortBlock:[:a1 :a2| a1 value >= a2 value].
	instSpace associationsDo:[:a| sorted add: a].
	sorted do:[:assoc|
		aStream cr; nextPutAll: assoc key; tab.
		aStream print: (instCount at: assoc key); nextPutAll:' instances '.
		aStream print: assoc value; nextPutAll: ' bytes '.
	].
	sum1 := instCount inject: 0 into:[:sum :n| sum + n].
	sum2 := instSpace inject: 0 into:[:sum :n| sum + n].
	aStream cr; cr.
	aStream print: sum1; nextPutAll:' instances '.
	aStream print: sum2; nextPutAll: ' bytes '.
]

{ #category : #'fileIn/Out' }
NativeImageSegment >> rehashSets [
	"I have just been brought in and converted to live objects.  Find all Sets and Dictionaries in the newly created objects and rehash them.  Segment is near then end of memory, since is was newly brought in (and a new object created for it).
	Also, collect all classes of receivers of blocks.  Return them.  Caller will check if they have been reshaped."

	| hashedCollections receiverClasses |
	hashedCollections := OrderedCollection new.
		"have to collect them, because Dictionary makes a copy, and that winds up at the end of memory and gets rehashed and makes another one."
	receiverClasses := IdentitySet new.
	self allObjectsDo:
		[:object|
		object isInMemory ifTrue:
			[(object isCollection and: [object isKindOf: HashedCollection]) ifTrue:
				[hashedCollections add: object].
			(object isBlock or: [object isContext]) ifTrue:
				[receiverClasses add: object receiver class]]].
	hashedCollections do: [ :each | each compact ]. "our purpose"
	^receiverClasses	"our secondary job"
]

{ #category : #'read/write segment' }
NativeImageSegment >> revert [
	"Pretend this segment was never brought in.  Check that it has a fileName.  Replace (using become:) all the original roots of a segment with segmentRootStubs.  Thus the original objects will be reclaimed, and the root stubs will remain to bring the segment back in if it is needed.
	How to use revert:  In the project, choose 'save for reverting'.

	ReEnter the project.  Make changes.
	Either exit normally, and change will be kept, or
		Choose 'Revert to saved version'."

	fileName ifNil: [^ self].
	(state = #inactive) | (state = #onFile) ifFalse: [^ self].
	Cursor write showWhile: [
		arrayOfRoots elementsForwardIdentityTo:
			(arrayOfRoots collect: [:r | r rootStubInImageSegment: self]).
		state := #onFile.
		segment := nil]

"Old version:
	How to use revert:  In the project, execute 
(Project current projectParameters at: #frozen put: true)
	Leave the project.  Check that the project went out to disk (it is gray in the Jump to Project list).
	ReEnter the project.  Hear a plink as it comes in from disk.  Make a change.
	Exit the project.  Choose 'Revert to previous version' in the dialog box.
	Check that the project went out to disk (it is gray in the Jump to Project list).
	ReEnter the project and see that it is in the original state."
]

{ #category : #'read/write segment' }
NativeImageSegment >> rootsIncludingBlockMethods [
	"Return a new roots array with more objects.  (Caller should store into rootArray.) Any CompiledMethods that create blocks will be in outPointers if the block is held outside of this segment.  Put such methods into the roots list.  Then ask for the segment again."

	| myClasses extras |
	userRootCnt ifNil: [userRootCnt := arrayOfRoots size].
	extras := OrderedCollection new.
	myClasses := OrderedCollection new.
	arrayOfRoots do: [:aRoot | aRoot class class == Metaclass ifTrue: [
					myClasses add: aRoot]].
	myClasses isEmpty ifTrue: [^ nil].	"no change"
	outPointers do: [:anOut | | gotIt | 
		anOut class == CompiledMethod ifTrue: [
			"specialized version of who"
			gotIt := false.
			myClasses detect: [:class |
				class methodsDo: [:m |
					m == anOut 
						ifTrue: [extras add: anOut.  gotIt := true]].
				gotIt] 
				ifNone: []
			].
	].
	extras := extras select: [:ea | (arrayOfRoots includes: ea) not].
	extras isEmpty ifTrue: [^ nil].	"no change"
	^ arrayOfRoots, extras
]

{ #category : #'read/write segment' }
NativeImageSegment >> rootsIncludingBlocks [
	"For export segments only.  Return a new roots array with more objects.  (Caller should store into rootArray.)  Collect Blocks and external methods pointed to by them.  Put them into the roots list.  Then ask for the segment again."

	| extras have |
	userRootCnt ifNil: [userRootCnt := arrayOfRoots size].
	extras := OrderedCollection new.
	outPointers do: [:anOut | 
		anOut class == CompiledMethod ifTrue: [extras add: anOut].
		(anOut isBlock) ifTrue: [extras add: anOut].
		(anOut class == Context) ifTrue: [extras add: anOut]].

	[have := extras size.
	 extras copy do: [:anOut |
		anOut isBlock ifTrue: [
			anOut home ifNotNil: [
				(extras includes: anOut home) ifFalse: [extras add: anOut home]]].
		(anOut class == Context) ifTrue: [
			anOut method ifNotNil: [
				(extras includes: anOut method) ifFalse: [extras add: anOut method]]]].
	 have = extras size] whileFalse.
	extras := extras select: [:ea | (arrayOfRoots includes: ea) not].
	extras isEmpty ifTrue: [^ nil].	"no change"

	^ arrayOfRoots, extras
]

{ #category : #access }
NativeImageSegment >> segment [
	^ segment
]

{ #category : #'read/write segment' }
NativeImageSegment >> segmentCopy [
	"This operation will install a copy of the segment in memory, and return a copy of the
	 array of roots. The effect is to perform a deep copy of the original structure.  Note that
	 installation destroys the segment, so it must be copied before doing the operation."

	| allObjectsInSegment newRoots |
	state = #activeCopy ifFalse: [self errorWrongState].
	allObjectsInSegment := self loadSegmentFrom: segment copy outPointers: outPointers.
	newRoots := allObjectsInSegment first.
	^newRoots
]

{ #category : #'read/write segment' }
NativeImageSegment >> segmentName [
	"Return the local file name for this segment."

	^ segmentName
]

{ #category : #'read/write segment' }
NativeImageSegment >> segmentName: aString [
	"Local file name for this segment."

	segmentName := aString
]

{ #category : #'read/write segment' }
NativeImageSegment >> smartFillRoots: dummy [
	| refs known ours ww blockers |
	"Put all traced objects into my arrayOfRoots.  Remove some
that want to be in outPointers.  Return blockers, an
IdentityDictionary of objects to replace in outPointers."

	blockers := dummy blockers.
	known := (refs := dummy references) size.
	refs keys do: [:obj | "copy keys to be OK with removing items"
		(obj isSymbol) ifTrue: [refs removeKey: obj.  known := known-1].
		(obj class == PasteUpMorph) ifTrue: [
			obj isWorldMorph & (obj owner == nil) ifTrue: [
				(dummy project ~~ nil and: [obj == dummy project world]) ifFalse: [
					refs removeKey: obj.  known := known-1.
					blockers at: obj put:
						(StringMorph contents: 'The worldMorph of a different world')]]].
					"Make a ProjectViewMorph here"
		"obj class == Project ifTrue: [Transcript show: obj; cr]."
		(blockers includesKey: obj) ifTrue: [
			refs removeKey: obj ifAbsent: [known := known+1].  known := known-1].
		].
	ours := dummy project ifNotNil: [dummy project world] ifNil: [ActiveWorld].
	refs keysDo: [:obj |
			obj isMorph ifTrue: [
				ww := obj world.
				(ww == ours) | (ww == nil) ifFalse: [
					refs removeKey: obj.  known := known-1.
					blockers at: obj put: (StringMorph contents:
								obj printString, ' from another world')]]].
	"keep original roots on the front of the list"
	dummy rootObject do: [:rr | refs removeKey: rr ifAbsent: []].
	(self respondsTo: #classOrganizersBeRoots:) ifTrue: "an EToys extension"
		[self classOrganizersBeRoots: dummy].
	^dummy rootObject, refs keys asArray
]

{ #category : #access }
NativeImageSegment >> state [
	^ state
]

{ #category : #'fileIn/Out' }
NativeImageSegment >> storeDataOn: aDataStream [
	"Don't wrote the array of Roots.  Also remember the structures of the classes of objects inside the segment."

	| tempRoots tempOutP list |
	state = #activeCopy ifFalse: [self error: 'wrong state'].
		"real state is activeCopy, but we changed it will be right when coming in"
	tempRoots := arrayOfRoots.
	tempOutP := outPointers.
	outPointers := outPointers shallowCopy.
	self prepareToBeSaved.
	arrayOfRoots := nil.
	state := #imported.
	super storeDataOn: aDataStream.		"record my inst vars"
	arrayOfRoots := tempRoots.
	outPointers := tempOutP.
	state := #activeCopy.
	aDataStream references at: #AnImageSegment put: false.	"the false is meaningless"
		"This key in refs is the flag that there is an ImageSegment in this file."

	"Find the receivers of blocks in the segment.  Need to get the structure of their classes into structures.  Put the receivers into references."
	(aDataStream byteStream isKindOf: DummyStream) ifTrue: [
		list := Set new.
		arrayOfRoots do: [:ea | 
			ea isBlock | (ea class == Context) ifTrue: [ 
				list add: ea receiver class ]].
		aDataStream references at: #BlockReceiverClasses put: list].
]

{ #category : #'read/write segment primitives' }
NativeImageSegment >> storeSegmentFor: rootsArray into: segmentWordArray outPointers: outPointerArray [
	"This primitive will store a binary image segment (in the same format as the Squeak
	 image file) of the receiver and every object in its proper tree of subParts (ie, that is
	 not refered to from anywhere else outside the tree).  Note: all elements of the reciever
	 are treated as roots in determining the extent of the tree.  All pointers from within
	 the tree to objects outside the tree will be copied into the array of outpointers.  In
	 their place in the image segment will be an oop equal to the offset in the outpointer
	 array (the first would be 4 or 8, depending on word size). but with the high bit set.

	 Note: the first element of the segmentWordArray (and hence the first element of
	 the Array answered by loadSegmentFrom:outPointers:) is the rootsArray."

	"The primitive expects the array and wordArray to be more than adequately long.
	 In this case it returns normally, and truncates the two arrays to exactly the right size.
	 If either array is too small, the primitive will fail, but in no other case."

	<primitive: 98 error: ec>	"successful completion returns self"
	^nil							"failure returns nil"
]

{ #category : #testing }
NativeImageSegment >> verify: ob1 matches: ob2 knowing: matchDict [

	| priorMatch first |
	ob1 == ob2 ifTrue:
		["If two pointers are same, they must be immediates or in outPointers"
		(ob1 class isImmediateClass and: [ob1 = ob2]) ifTrue: [^self].
		(outPointers includes: ob1) ifTrue: [^ self].
		self halt].
	priorMatch := matchDict at: ob1 ifAbsent: [nil].
	priorMatch == nil
		ifTrue: [matchDict at: ob1 put: ob2]
		ifFalse: [priorMatch == ob2
					ifTrue: [^ self]
					ifFalse: [self halt]].
	self verify: ob1 class matches: ob2 class knowing: matchDict.
	ob1 class isVariable ifTrue: 
		[ob1 basicSize = ob2 basicSize ifFalse: [self halt].
		first := 1.
		ob1 isCompiledMethod ifTrue: [first := ob1 initialPC].
		first to: ob1 basicSize do:
			[:i | self verify: (ob1 basicAt: i) matches: (ob2 basicAt: i) knowing: matchDict]].
	ob1 class instSize = ob2 class instSize ifFalse: [self halt].
	1 to: ob1 class instSize do:
		[:i | self verify: (ob1 instVarAt: i) matches: (ob2 instVarAt: i) knowing: matchDict].
	ob1 isCompiledMethod ifTrue:
		[ob1 header = ob2 header ifFalse: [self halt].
		ob1 numLiterals = ob2 numLiterals ifFalse: [self halt].
		1 to: ob1 numLiterals do:
			[:i | self verify: (ob1 literalAt: i) matches: (ob2 literalAt: i) knowing: matchDict]]
]

{ #category : #testing }
NativeImageSegment >> verifyCopy [

	| copyOfRoots matchDict |
	copyOfRoots := self segmentCopy.
	matchDict := IdentityDictionary new.
	arrayOfRoots with: copyOfRoots do:
		[:r :c | self verify: r matches: c knowing: matchDict]
]
