"
This is the save-to-disk facility. A DataStream can store one or more objects in a persistent form.

To handle objects with sharing and cycles, you must use a
ReferenceStream instead of a DataStream.  (Or SmartRefStream.)  ReferenceStream is typically
faster and produces smaller files because it doesn't repeatedly write the same Symbols.

Here is the way to use DataStream and ReferenceStream:
	rr := ReferenceStream fileNamed: 'test.obj'.
	rr nextPut: <your object>.
	rr close.

To get it back:
	rr := ReferenceStream fileNamed: 'test.obj'.
	<your object> := rr next.
	rr close.

Each object to be stored has two opportunities to control what gets stored.  On the high level, objectToStoreOnDataStream allows you to substitute another object on the way out.  The low level hook is storeDataOn:. The read-in counterparts to these messages are comeFullyUpOnReload and (class) readDataFrom:size:. See these methods, and the class DiskProxy, for more information about externalizing and internalizing.

NOTE: A DataStream should be treated as a write-stream for writing.  It is a read-stream for reading.  It is not a ReadWriteStream.

"
Class {
	#name : #DataStream,
	#superclass : #Stream,
	#instVars : [
		'byteStream',
		'topCall',
		'basePos'
	],
	#classVars : [
		'TypeMap'
	],
	#category : #'System-Object Storage'
}

{ #category : #'class initialization' }
DataStream class >> cleanUp [
	"Re-initialize DataStream to avoid hanging onto obsolete classes"

	self initialize
]

{ #category : #'as yet unclassified' }
DataStream class >> example [
    "An example and test of DataStream/ReferenceStream.
     11/19/92 jhm: Use self testWith:."
    "DataStream example"
    "ReferenceStream example"
    | input sharedPoint |

    "Construct the test data."
    input := Array new: 10.
    input at: 1 put: nil.
    input at: 2 put: true.
    input at: 3 put: (Form extent: 63 @ 50 depth: 8).
		(input at: 3) fillWithColor: Color lightBlue.
    input at: 4 put: #(3 3.0 'three').
    input at: 5 put: false.
    input at: 6 put: 1024 @ -2048.
    input at: 7 put: #x.
    input at: 8 put: (Array with: (sharedPoint := 0 @ -30000)).
    input at: 9 put: sharedPoint.
    input at: 10 put: (Character value: 16r200d).

    "Write it out, read it back, and return it for inspection."
    ^ self testWith: input
]

{ #category : #'as yet unclassified' }
DataStream class >> exampleWithPictures [
	"DataStream exampleWithPictures"
	| file result |
	file := FileStream fileNamed: 'Test-Picture'.
	file binary.
	(DataStream on: file) nextPut: (Form fromUser).
	file close.

	file := FileStream fileNamed: 'Test-Picture'.
	file binary.
	result := (DataStream on: file) next.
	file close.
	result display.
	^ result
]

{ #category : #'as yet unclassified' }
DataStream class >> fileNamed: aString [
	"Here is the way to use DataStream and ReferenceStream:
rr := ReferenceStream fileNamed: 'test.obj'.
rr nextPut: <your object>.
rr close.
"

	^ self on: (FileStream fileNamed: aString).	"will be binary"
]

{ #category : #'as yet unclassified' }
DataStream class >> initialize [
	"TypeMap maps Smalltalk classes to type ID numbers which identify the data stream primitive formats.  nextPut: writes these IDs to the data stream.  NOTE: Changing these type ID numbers will invalidate all extant data stream files.  Adding new ones is OK.  
	Classes named here have special formats in the file.  If such a class has a subclass, it will use type 9 and write correctly.  It will just be slow.  (Later write the class name in the special format, then subclasses can use the type also.)
	 See nextPut:, next, typeIDFor:, & ReferenceStream>>isAReferenceType:"
	"DataStream initialize"

	| refTypes t |
	refTypes := OrderedCollection new.
	t := TypeMap := WeakIdentityKeyDictionary new. "It has to be weak, because some classes may go away, leaving obsolete versions in this dictionary which may make it corrupt."

	t at: UndefinedObject put: 1.   refTypes add: 0.
	t at: True put: 2.   refTypes add: 0.
	t at: False put: 3.   refTypes add: 0.
	t at: SmallInteger put: 4.	 refTypes add: 0.
	t at: ByteString put: 5.   refTypes add: 1.
	t at: ByteSymbol put: 6.   refTypes add: 1.
	t at: ByteArray put: 7.   refTypes add: 1.
	t at: Array put: 8.   refTypes add: 1.
	"(type ID 9 is for arbitrary instances of any class, cf. typeIDFor:)"
		refTypes add: 1.
	"(type ID 10 is for references, cf. ReferenceStream>>tryToPutReference:)"
		refTypes add: 0.
	t at: Bitmap put: 11.   refTypes add: 1.
	t at: Metaclass put: 12.   refTypes add: 0.
	"Type ID 13 is used for HyperSqueak User classes that must be reconstructed."
		refTypes add: 1.
	t at: Float put: 14.  refTypes add: 1.
	t at: Rectangle put: 15.  refTypes add: 1.	"Allow compact Rects."
	"type ID 16 is an instance with short header.  See beginInstance:size:"
		refTypes add: 1.
self flag: #ByteArray.
	t at: ByteString put: 17.   refTypes add: 1.	"new String format, 1 or 4 bytes of length"
	t at: WordArray put: 18.  refTypes add: 1.	"bitmap-like"
	t at: WordArrayForSegment put: 19.  refTypes add: 1.		"bitmap-like"
	"t at: SoundBuffer put: 20.  refTypes add: 1."	"And all other word arrays, both 
		16-bit and 32-bit.  See methods in ArrayedCollection.  Overridden in SoundBuffer."
	t at: CompiledMethod put: 21.  refTypes add: 1.	"special creation method"
	"t at:  put: 22.  refTypes add: 0."
	ReferenceStream refTypes: refTypes.		"save it"

	"For all classes that are like WordArrays, store them the way ColorArray is stored.  As bits, and able to change endianness."
	Smalltalk globals do: [:cls |
		(cls isInMemory and: [
			cls isBehavior and: [
			(self isClassObsolete: cls) not and: [
			cls isPointers not and: [
			cls isVariable and: [
			cls isWords and: [
			(t includesKey: cls) not ] ] ] ] ] ]) 
				ifTrue: [ t at: cls put: 20 ] ]
]

{ #category : #testing }
DataStream class >> isClassObsolete: aClass [
	| instanceSide |
	instanceSide := aClass instanceSide.
	^ (instanceSide environment
			at: instanceSide name
			ifAbsent: [ ^ true ]) ~~ instanceSide
]

{ #category : #'as yet unclassified' }
DataStream class >> new [
	^ self basicNew
]

{ #category : #'as yet unclassified' }
DataStream class >> newFileNamed: aString [
	"Here is the way to use DataStream and ReferenceStream:
rr := ReferenceStream fileNamed: 'test.obj'.
rr nextPut: <your object>.
rr close.
"

	^ self on: (FileStream newFileNamed: aString).	"will be binary"
]

{ #category : #'as yet unclassified' }
DataStream class >> oldFileNamed: aString [
	"Here is the way to use DataStream and ReferenceStream:
rr := ReferenceStream oldFileNamed: 'test.obj'.
^ rr nextAndClose.
"

	| strm ff |
	ff := FileStream oldFileOrNoneNamed: aString.
	ff ifNil: [^ nil].
	strm := self on: (ff binary).
	^ strm
]

{ #category : #'as yet unclassified' }
DataStream class >> on: aStream [
	"Open a new DataStream onto a low-level I/O stream."

	^ self basicNew setStream: aStream
		"aStream binary is in setStream:"

]

{ #category : #'as yet unclassified' }
DataStream class >> streamedRepresentationOf: anObject [

	| file |
	file := (RWBinaryOrTextStream on: (ByteArray new: 5000)).
	file binary.
	(self on: file) nextPut: anObject.
	^file contents
]

{ #category : #'as yet unclassified' }
DataStream class >> testWith: anObject [
	"As a test of DataStream/ReferenceStream, write out anObject and read it back.
	11/19/92 jhm: Set the file type. More informative file name."
	"DataStream testWith: 'hi'"
	"ReferenceStream testWith: 'hi'"
	| file result |

	file := FileStream fileNamed: (self name, ' test').
	file binary.
	(self on: file) nextPut: anObject.
	file close.

	file := FileStream fileNamed: (self name, ' test').
	file binary.
	result := (self on: file) next.
	file close.
	(anObject class whichClassIncludesSelector: #=) == Object ifFalse:
		[self assert: result = anObject].
	^result
]

{ #category : #'as yet unclassified' }
DataStream class >> unStream: aString [

	^(self on: ((RWBinaryOrTextStream with: aString) reset; binary)) next
]

{ #category : #other }
DataStream >> atEnd [
    "Answer true if the stream is at the end."

    ^ byteStream atEnd
]

{ #category : #'write and read' }
DataStream >> beginInstance: aClass size: anInteger [
	"This is for use by storeDataOn: methods.
	 Cf. Object>>storeDataOn:."

		"Addition of 1 seems to make extra work, since readInstance
		has to compensate.  Here for historical reasons dating back
		to Kent Beck's original implementation in late 1988.

		In ReferenceStream, class is just 5 bytes for shared symbol.

		SmartRefStream puts out the names and number of class's instances variables for checking."

	byteStream nextNumber: 4 put: anInteger + 1.

	self nextPut: aClass name
]

{ #category : #'write and read' }
DataStream >> beginReference: anObject [
    "We're starting to read anObject. Remember it and its reference
     position (if we care; ReferenceStream cares). Answer the
     reference position."

    ^ 0
]

{ #category : #other }
DataStream >> byteStream [
	^ byteStream
]

{ #category : #other }
DataStream >> close [
	"Close the stream."

	| bytes |
	byteStream closed 
		ifFalse: [
			bytes := byteStream position.
			byteStream close]
		ifTrue: [bytes := 'unknown'].
	^ bytes
]

{ #category : #other }
DataStream >> contents [
	^byteStream contents
]

{ #category : #other }
DataStream >> errorWriteReference: anInteger [
    "PRIVATE -- Raise an error because this case of nextPut:'s perform:
     shouldn't be called. -- 11/15/92 jhm"

    self error: 'This should never be called'
]

{ #category : #other }
DataStream >> flush [
    "Guarantee that any writes to me are actually recorded on disk. -- 11/17/92 jhm"

    ^ byteStream flush
]

{ #category : #'write and read' }
DataStream >> getCurrentReference [
    "PRIVATE -- Return the currentReference posn.
     Overridden by ReferenceStream."

    ^ 0
]

{ #category : #'write and read' }
DataStream >> insideASegment [
	^ false
]

{ #category : #'write and read' }
DataStream >> maybeBeginReference: internalObject [
	"Do nothing.  See ReferenceStream|maybeBeginReference:"

	^ internalObject
]

{ #category : #'write and read' }
DataStream >> next [
	"Answer the next object in the stream."
	| type selector anObject isARefType pos internalObject |

	type := byteStream next.
	type ifNil: [pos := byteStream position.	"absolute!!"
		byteStream close.	"clean up"
		byteStream position = 0 
			ifTrue: [self error: 'The file did not exist in this directory'] 
			ifFalse: [self error: 'Unexpected end of object file'].
		pos.	"so can see it in debugger"
		^ nil].
	type = 0 ifTrue: [pos := byteStream position.	"absolute!!"
		byteStream close.	"clean up"
		self error: 'Expected start of object, but found 0'.
		^ nil].
	isARefType := self noteCurrentReference: type.
	selector := #(readNil readTrue readFalse readInteger	"<-4"
			readStringOld readSymbol readByteArray		"<-7"
			readArray readInstance readReference readBitmap	"<-11"
			readClass readUser readFloat readRectangle readShortInst 	"<-16"
			readString readWordArray readWordArrayForSegment 	"<-19"
			readWordLike readMethod "<-21") at: type ifAbsent: [
				pos := byteStream position.	"absolute!!"
				byteStream close. 
				self error: 'file is more recent than this system'. ^ nil].
	anObject := self perform: selector. "A method that recursively
		calls next (readArray, readInstance, objectAt:) must save &
		restore the current reference position."
	isARefType ifTrue: [self beginReference: anObject].

		"After reading the externalObject, internalize it.
		 #readReference is a special case. Either:
		   (1) We actually have to read the object, recursively calling
			   next, which internalizes the object.
		   (2) We just read a reference to an object already read and
			   thus already interalized.
		 Either way, we must not re-internalize the object here."
	selector == #readReference ifTrue: [^ anObject].
	internalObject := anObject comeFullyUpOnReload: self.
	internalObject == String ifTrue:[
		"This is a hack to figure out if we're loading a String class 
		that really should be a ByteString. Note that these days this
		will no longer be necessary since we use #withClassVersion:
		for constructing the global thus using a different classVersion
		will perfectly do the trick."
		((anObject isKindOf: DiskProxy) 
			and:[anObject globalObjectName == #String
			and:[anObject constructorSelector == #yourself]]) ifTrue:[
				internalObject := ByteString]].
	^ self maybeBeginReference: internalObject
]

{ #category : #other }
DataStream >> next: anInteger [
    "Answer an Array of the next anInteger objects in the stream."
    | array |

    array := Array new: anInteger.
    1 to: anInteger do: [:i |
        array at: i put: self next].
    ^ array
]

{ #category : #other }
DataStream >> nextAndClose [
	"Speedy way to grab one object.  Only use when we are inside an object binary file.  Do not use for the start of a SmartRefStream mixed code-and-object file."

	| obj |
	obj := self next.
	self close.
	^ obj
]

{ #category : #'write and read' }
DataStream >> nextPut: anObject [
	"Write anObject to the receiver stream. Answer anObject."
	| typeID selector objectToStore |

	typeID := self typeIDFor: anObject.
	(self tryToPutReference: anObject typeID: typeID)
		ifTrue: [^ anObject].

	objectToStore := (self objectIfBlocked: anObject) objectForDataStream: self.
	objectToStore == anObject
		ifFalse:
			[typeID := self typeIDFor: objectToStore.
			(self tryToPutReference: objectToStore typeID: typeID)
				ifTrue: [^ anObject]].

	byteStream nextPut: typeID.
	selector := #(writeNil: writeTrue: writeFalse: writeInteger: 
		writeStringOld: writeSymbol: writeByteArray:
		writeArray: writeInstance: errorWriteReference: writeBitmap:
		writeClass: writeUser: writeFloat: writeRectangle: == "<-16 short inst" 
		writeString: writeBitmap: writeBitmap: writeWordLike: 
		writeInstance: "CompiledMethod") at: typeID.
	self perform: selector with: objectToStore.

	^ anObject


"NOTE: If anObject is a reference type (one that we write cross-references to) but its externalized form (result of objectForDataStream:) isn't (e.g. CompiledMethod and ViewState), then we should remember its externalized form
 but not add to 'references'. Putting that object again should just put its
 external form again. That's more compact and avoids seeks when reading.
 But we just do the simple thing here, allowing backward-references for
 non-reference types like nil. So objectAt: has to compensate. Objects that
 externalize nicely won't contain the likes of ViewStates, so this shouldn't
 hurt much.
	 writeReference: -> errorWriteReference:."
]

{ #category : #'write and read' }
DataStream >> nextPutAll: aCollection [
    "Write each of the objects in aCollection to the
     receiver stream. Answer aCollection."

    ^ aCollection do: [:each | self nextPut: each]
]

{ #category : #'write and read' }
DataStream >> noteCurrentReference: typeID [
    "PRIVATE -- If we support references for type typeID, remember
     the current byteStream position so we can add the next object to
     the 'objects' dictionary, and return true. Else return false.
     This method is here to be overridden by ReferenceStream"

    ^ false
]

{ #category : #'write and read' }
DataStream >> objectAt: anInteger [
	"PRIVATE -- Read & return the object at a given stream position.  anInteger is a relative file position. "
	| savedPosn anObject refPosn |

	savedPosn := byteStream position.	"absolute"
	refPosn := self getCurrentReference.	"relative position"

	byteStream position: anInteger + basePos.	"was relative"
	anObject := self next.

	self setCurrentReference: refPosn.	"relative position"
	byteStream position: savedPosn.		"absolute"
	^ anObject
]

{ #category : #'write and read' }
DataStream >> objectIfBlocked: anObject [
	"We don't do any blocking"

	^ anObject
]

{ #category : #'write and read' }
DataStream >> outputReference: referencePosn [
	"PRIVATE -- Output a reference to the object at integer stream position referencePosn (relative to basePos). To output a weak reference to an object not yet written, supply (self vacantRef) for referencePosn."

	byteStream nextPut: 10. "reference typeID"
	byteStream nextNumber: 4 put: referencePosn	"relative position"
]

{ #category : #other }
DataStream >> project [
	^nil
]

{ #category : #'write and read' }
DataStream >> readArray [
	"PRIVATE -- Read the contents of an Array.
	 We must do beginReference: here after instantiating the Array
	 but before reading its contents, in case the contents reference
	 the Array. beginReference: will be sent again when we return to
	 next, but that's ok as long as we save and restore the current
	 reference position over recursive calls to next."
	| count array refPosn |

	count := byteStream nextNumber: 4.

	refPosn := self beginReference: (array := Array new: count).		"relative pos"
	1 to: count do: [:i |
		array at: i put: self next].
	self setCurrentReference: refPosn.		"relative pos"
	^ array
]

{ #category : #'write and read' }
DataStream >> readBitmap [
	"PRIVATE -- Read the contents of a Bitmap."

	^ Bitmap newFromStream: byteStream
	"Note that the reader knows that the size is in long words, but the data is in bytes."
]

{ #category : #'write and read' }
DataStream >> readBoolean [
	"PRIVATE -- Read the contents of a Boolean.
	 This is here only for compatibility with old data files."

	^ byteStream next ~= 0
]

{ #category : #'write and read' }
DataStream >> readByteArray [
	"PRIVATE -- Read the contents of a ByteArray."

	| count |
	count := byteStream nextNumber: 4.
	^ byteStream next: count  "assume stream is in binary mode"

]

{ #category : #'write and read' }
DataStream >> readClass [
	"Should never be executed because a DiskProxy, not a clas comes in."

	^ self error: 'Classes should be filed in'
]

{ #category : #'write and read' }
DataStream >> readFalse [
    "PRIVATE -- Read the contents of a False."

    ^ false
]

{ #category : #'write and read' }
DataStream >> readFloat [
	"PRIVATE -- Read the contents of a Float.
	 This is the fast way to read a Float.
	 We support 8-byte Floats here.  Non-IEEE"

	| new |
	new := Float new: 2.		"To get an instance"
	new at: 1 put: (byteStream nextNumber: 4).
	new at: 2 put: (byteStream nextNumber: 4).
	^ new
]

{ #category : #'write and read' }
DataStream >> readFloatString [
	"PRIVATE -- Read the contents of a Float string.
	 This is the slow way to read a Float--via its string rep'n.
	 It's here for compatibility with old data files."

	^ Float readFrom: (byteStream next: (byteStream nextNumber: 4))
]

{ #category : #'write and read' }
DataStream >> readInstance [
	"PRIVATE -- Read the contents of an arbitrary instance.
	 ASSUMES: readDataFrom:size: sends me beginReference: after it
	   instantiates the new object but before reading nested objects.
	 NOTE: We must restore the current reference position after
	   recursive calls to next.
	Let the instance, not the class read the data.  "
	| instSize aSymbol refPosn anObject newClass |

	instSize := (byteStream nextNumber: 4) - 1.
	refPosn := self getCurrentReference.
	aSymbol := self next.
	newClass := Smalltalk at: aSymbol asSymbol.
	self setCurrentReference: refPosn.  "before readDataFrom:size:"
	anObject := newClass isImmediateClass
		ifTrue: [newClass readImmediateFrom: self size: instSize]
		ifFalse: [anObject := newClass isVariable 	"Create object here"
			ifFalse: [newClass basicNew]
			ifTrue: [newClass basicNew: instSize - (newClass instSize)].
		anObject readDataFrom: self size: instSize].
	self setCurrentReference: refPosn.  "before returning to next"
	^ anObject
]

{ #category : #'write and read' }
DataStream >> readInteger [
    "PRIVATE -- Read the contents of a SmallInteger."

    ^ byteStream nextInt32	"signed!!!"
]

{ #category : #'write and read' }
DataStream >> readMethod [
	"PRIVATE -- Read the contents of an arbitrary instance.
	 ASSUMES: readDataFrom:size: sends me beginReference: after it
	   instantiates the new object but before reading nested objects.
	 NOTE: We must restore the current reference position after
	   recursive calls to next.
	Let the instance, not the class read the data.  "
	| instSize refPosn newClass className xxHeader nLits byteCodeSizePlusTrailer newMethod lits |

	instSize := (byteStream nextNumber: 4) - 1.
	refPosn := self getCurrentReference.
	className := self next.
	newClass := Smalltalk at: className asSymbol.

	xxHeader := self next.
		"nArgs := (xxHeader >> 24) bitAnd: 16rF."
		"nTemps := (xxHeader >> 18) bitAnd: 16r3F."
		"largeBit := (xxHeader >> 17) bitAnd: 1."
	nLits := xxHeader bitAnd: 16r7FFF.
	byteCodeSizePlusTrailer := instSize - (newClass instSize "0") - (nLits + 1 * Smalltalk wordSize).

	newMethod := newClass 
						newMethod: byteCodeSizePlusTrailer
						header: xxHeader.

	self setCurrentReference: refPosn.  "before readDataFrom:size:"
	self beginReference: newMethod.
	lits := newMethod numLiterals + 1.	"counting header"
	2 to: lits do:
		[:ii | newMethod objectAt: ii put: self next].
	lits*Smalltalk wordSize+1 to: newMethod basicSize do:
		[:ii | newMethod basicAt: ii put: byteStream next].
			"Get raw bytes directly from the file"
	self setCurrentReference: refPosn.  "before returning to next"
	^newMethod
]

{ #category : #'write and read' }
DataStream >> readNil [
    "PRIVATE -- Read the contents of an UndefinedObject."

    ^ nil
]

{ #category : #'write and read' }
DataStream >> readRectangle [
    "Read a compact Rectangle.  Rectangles with values outside +/- 2047 were stored as normal objects (type=9).  They will not come here.  17:22 tk"

	"Encoding is four 12-bit signed numbers.  48 bits in next 6 bytes.  17:24 tk"
	| acc left top right bottom |
	acc := byteStream nextNumber: 3.
	left := acc bitShift: -12.
	(left bitAnd: 16r800) ~= 0 ifTrue: [left := left - 16r1000].	"sign"
	top := acc bitAnd: 16rFFF.
	(top bitAnd: 16r800) ~= 0 ifTrue: [top := top - 16r1000].	"sign"

	acc := byteStream nextNumber: 3.
	right := acc bitShift: -12.
	(right bitAnd: 16r800) ~= 0 ifTrue: [right := right - 16r1000].	"sign"
	bottom := acc bitAnd: 16rFFF.
	(bottom bitAnd: 16r800) ~= 0 ifTrue: [bottom := bottom - 16r1000].	"sign"
	
    ^ Rectangle left: left right: right top: top bottom: bottom

]

{ #category : #'write and read' }
DataStream >> readReference [
	"Read the contents of an object reference. (Cf. outputReference:)  File is not now positioned at this object."
	| referencePosition |

	^ (referencePosition := (byteStream nextNumber: 4)) = self vacantRef	"relative"
		ifTrue:  [nil]
		ifFalse: [self objectAt: referencePosition]		"relative pos"
]

{ #category : #'write and read' }
DataStream >> readShortInst [
	"Read the contents of an arbitrary instance that has a short header.
	 ASSUMES: readDataFrom:size: sends me beginReference: after it
	   instantiates the new object but before reading nested objects.
	 NOTE: We must restore the current reference position after
	   recursive calls to next.
	Let the instance, not the class read the data.  "
	| instSize aSymbol refPosn anObject newClass |

	instSize := (byteStream next) - 1.	"one byte of size"
	refPosn := self getCurrentReference.
	aSymbol := self readShortRef.	"class symbol in two bytes of file pos"
	newClass := Smalltalk at: aSymbol asSymbol.
	anObject := newClass isVariable 	"Create object here"
			ifFalse: [newClass basicNew]
			ifTrue: [newClass basicNew: instSize - (newClass instSize)].
	self setCurrentReference: refPosn.  "before readDataFrom:size:"
	anObject := anObject readDataFrom: self size: instSize.
	self setCurrentReference: refPosn.  "before returning to next"
	^ anObject
]

{ #category : #'write and read' }
DataStream >> readShortRef [
	"Read an object reference from two bytes only.  Original object must be in first 65536 bytes of the file.  Relative to start of data.  vacantRef not a possibility."

	^ self objectAt: (byteStream nextNumber: 2)
]

{ #category : #'write and read' }
DataStream >> readString [
	^byteStream nextString

]

{ #category : #'write and read' }
DataStream >> readStringOld [

   ^ byteStream nextStringOld
]

{ #category : #'write and read' }
DataStream >> readSymbol [
    "PRIVATE -- Read the contents of a Symbol."

    ^ self readString asSymbol
]

{ #category : #'write and read' }
DataStream >> readTrue [
    "PRIVATE -- Read the contents of a True."

    ^ true
]

{ #category : #'write and read' }
DataStream >> readUser [
	"Reconstruct both the private class and the instance.  Still used??"

	^ self readInstance.		"Will create new unique class"

]

{ #category : #'write and read' }
DataStream >> readWordArray [
	"PRIVATE -- Read the contents of a WordArray."

	^ WordArray newFromStream: byteStream
	"Size is number of long words."
]

{ #category : #'write and read' }
DataStream >> readWordArrayForSegment [
	"Read the contents of a WordArray ignoring endianness."

	^ WordArrayForSegment newFromStream: byteStream
	"Size is number of long words."
]

{ #category : #'write and read' }
DataStream >> readWordLike [
	| refPosn aSymbol newClass anObject |
	"Can be used by any class that is bits and not bytes (WordArray, Bitmap, SoundBuffer, etc)."

	refPosn := self getCurrentReference.
	aSymbol := self next.
	newClass := Smalltalk at: aSymbol asSymbol.
	anObject := newClass newFromStream: byteStream.
	"Size is number of long words."
	self setCurrentReference: refPosn.  "before returning to next"
	^ anObject

]

{ #category : #'write and read' }
DataStream >> replace: original with: proxy [
	"We may wish to remember that in some field, the original object is being replaced by the proxy.  For the hybred scheme that collects with a DummyStream and writes an ImageSegment, it needs to hold onto the originals so they will appear in outPointers, and be replaced."

	"do nothing"
]

{ #category : #other }
DataStream >> reset [
    "Reset the stream."

    byteStream reset
]

{ #category : #other }
DataStream >> rootObject [
	"Return the object at the root of the tree we are filing out.  "

	^ topCall
]

{ #category : #other }
DataStream >> rootObject: anObject [
	"Return the object at the root of the tree we are filing out.  "

	topCall := anObject
]

{ #category : #'write and read' }
DataStream >> setCurrentReference: refPosn [
    "PRIVATE -- Set currentReference to refPosn.
     Noop here. Cf. ReferenceStream."
]

{ #category : #other }
DataStream >> setStream: aStream [
	"PRIVATE -- Initialization method."

	aStream binary.
	basePos := aStream position.	"Remember where we start.  Earlier part of file contains a class or method file-in.  Allow that to be edited.  We don't deal in absolute file locations."
	byteStream := aStream.
]

{ #category : #other }
DataStream >> setStream: aStream reading: isReading [
	"PRIVATE -- Initialization method."

	aStream binary.
	basePos := aStream position.	"Remember where we start.  Earlier part of file contains a class or method file-in.  Allow that to be edited.  We don't deal in absolute file locations."
	byteStream := aStream.
]

{ #category : #other }
DataStream >> size [
    "Answer the stream's size."

    ^ byteStream size
]

{ #category : #'write and read' }
DataStream >> tryToPutReference: anObject typeID: typeID [
    "PRIVATE -- If we support references for type typeID, and if
       anObject already appears in my output stream, then put a
       reference to the place where anObject already appears. If we
       support references for typeID but didn't already put anObject,
       then associate the current stream position with anObject in
       case one wants to nextPut: it again.
     Return true after putting a reference; false if the object still
       needs to be put.
     For DataStream this is trivial. ReferenceStream overrides this."

    ^ false
]

{ #category : #'write and read' }
DataStream >> typeIDFor: anObject [
	"Return the typeID for anObject's class.  This is where the tangle of objects is clipped to stop everything from going out.  
	Classes can control their instance variables by defining objectToStoreOnDataStream.
	Any object in blockers is not written out.  See ReferenceStream.objectIfBlocked: and DataStream nextPut:.
	Morphs do not write their owners.  See Morph.storeDataOn:   Each morph tells itself to 'prepareToBeSaved' before writing out."


	anObject isFloat ifTrue: [^14]. "shortcut floats of any representation."
	^ TypeMap at: anObject class ifAbsent: [9 "instance of any normal class"]	
"See DataStream initialize.  nil=1. true=2. false=3. a SmallInteger=4. (a String was 5). a Symbol=6.  a ByteArray=7. an Array=8. other = 9.  a Bitmap=11. a Metaclass=12. a Float=14.  a Rectangle=15. any instance that can have a short header=16.  a String=17 (new format). a WordArray=18."
]

{ #category : #other }
DataStream >> vacantRef [
	"Answer the magic 32-bit constant we use ***ON DISK*** as a stream 'reference
	 position' to identify a reference that's not yet filled in. This must be a
	 value that won't be used as an ordinary reference. Cf. outputReference: and
	 readReference. -- 
	 NOTE: We could use a different type ID for vacant-refs rather than writing
		object-references with a magic value. (The type ID and value are
		overwritten by ordinary object-references when weak refs are fullfilled.)"

	^1073741823		"Hardcode former SmallInteger maxVal"
]

{ #category : #'write and read' }
DataStream >> writeArray: anArray [
	"PRIVATE -- Write the contents of an Array."

	byteStream nextNumber: 4 put: anArray size.
	self nextPutAll: anArray.
]

{ #category : #'write and read' }
DataStream >> writeBitmap: aBitmap [
	"PRIVATE -- Write the contents of a Bitmap."

	aBitmap writeOn: byteStream
	"Note that this calls (byteStream nextPutAll: aBitmap) which knows enough to put 4-byte quantities on the stream!  Reader must know that size is in long words."
]

{ #category : #'write and read' }
DataStream >> writeBoolean: aBoolean [
    "PRIVATE -- Write the contents of a Boolean.
     This method is now obsolete."

    byteStream nextPut: (aBoolean ifTrue: [1] ifFalse: [0])
]

{ #category : #'write and read' }
DataStream >> writeByteArray: aByteArray [
	"PRIVATE -- Write the contents of a ByteArray."

	byteStream nextNumber: 4 put: aByteArray size.
	"May have to convert types here..."
	byteStream nextPutAll: aByteArray.
]

{ #category : #'write and read' }
DataStream >> writeClass: aClass [
	"Write out a DiskProxy for the class.  It will look up the class's name in Smalltalk in the new sustem.  Never write classes or methodDictionaries as objects.  For novel classes, front part of file is a fileIn of the new class."

	"This method never executed because objectToStoreOnDataStream returns a DiskProxy.  See DataStream.nextPut:"
    ^ self error: 'Write a DiskProxy instead'
]

{ #category : #'write and read' }
DataStream >> writeFalse: aFalse [
    "PRIVATE -- Write the contents of a False."
]

{ #category : #'write and read' }
DataStream >> writeFloat: aFloat [
	"PRIVATE -- Write the contents of a Float.
	  We support 8-byte Floats here."

	byteStream nextNumber: 4 put: (aFloat at: 1).
	byteStream nextNumber: 4 put: (aFloat at: 2).

]

{ #category : #'write and read' }
DataStream >> writeFloatString: aFloat [
    "PRIVATE -- Write the contents of a Float string.
     This is the slow way to write a Float--via its string rep'n."

    self writeByteArray: (aFloat printString)
]

{ #category : #'write and read' }
DataStream >> writeInstance: anObject [
    "PRIVATE -- Write the contents of an arbitrary instance."

    ^ anObject storeDataOn: self
]

{ #category : #'write and read' }
DataStream >> writeInteger: anInteger [
	"PRIVATE -- Write the contents of a SmallInteger."

	byteStream nextInt32Put: anInteger	"signed!!!!!"
]

{ #category : #'write and read' }
DataStream >> writeNil: anUndefinedObject [
    "PRIVATE -- Write the contents of an UndefinedObject."
]

{ #category : #'write and read' }
DataStream >> writeRectangle: anObject [
    "Write the contents of a Rectangle.  See if it can be a compact Rectangle (type=15).  Rectangles with values outside +/- 2047 were stored as normal objects (type=9).  17:22 tk"

	| ok right bottom top left acc |
	ok := true.
	(right := anObject right) > 2047 ifTrue: [ok := false].
	right < -2048 ifTrue: [ok := false].
	(bottom := anObject bottom) > 2047 ifTrue: [ok := false].
	bottom < -2048 ifTrue: [ok := false].
	(top := anObject top) > 2047 ifTrue: [ok := false].
	top < -2048 ifTrue: [ok := false].
	(left := anObject left) > 2047 ifTrue: [ok := false].
	left < -2048 ifTrue: [ok := false].
	ok := ok & left isInteger & right isInteger & top isInteger & bottom isInteger.

	ok ifFalse: [
		byteStream skip: -1; nextPut: 9; skip: 0. "rewrite type to be normal instance"
	    ^ anObject storeDataOn: self].

	acc := ((left bitAnd: 16rFFF) bitShift: 12) + (top bitAnd: 16rFFF).
	byteStream nextNumber: 3 put: acc.
	acc := ((right bitAnd: 16rFFF) bitShift: 12) + (bottom bitAnd: 16rFFF).
	byteStream nextNumber: 3 put: acc.
]

{ #category : #'write and read' }
DataStream >> writeString: aString [
	"PRIVATE -- Write the contents of a String."

	byteStream nextStringPut: aString.
]

{ #category : #'write and read' }
DataStream >> writeStringOld: aString [
	"PRIVATE -- Write the contents of a String."

	| length |
	aString size < 16384 
		ifTrue: [
			(length := aString size) < 192
				ifTrue: [byteStream nextPut: length]
				ifFalse: 
					[byteStream nextPut: (length // 256 + 192).
					byteStream nextPut: (length \\ 256)].
			aString do: [:char | byteStream nextPut: char asciiValue]]
		ifFalse: [self writeByteArray: aString].	"takes more space"
]

{ #category : #'write and read' }
DataStream >> writeSymbol: aSymbol [
    "PRIVATE -- Write the contents of a Symbol."

    self writeString: aSymbol
]

{ #category : #'write and read' }
DataStream >> writeTrue: aTrue [
    "PRIVATE -- Write the contents of a True."
]

{ #category : #'write and read' }
DataStream >> writeUser: anObject [
    "Write the contents of an arbitrary User instance (and its devoted class)."
    " 7/29/96 tk"

	"If anObject is an instance of a unique user class, will lie and say it has a generic class"
    ^ anObject storeDataOn: self
]

{ #category : #'write and read' }
DataStream >> writeWordLike: aWordArray [
	"Note that we put the class name before the size."

	self nextPut: aWordArray class name.
	aWordArray writeOn: byteStream
	"Note that this calls (byteStream nextPutAll: aBitmap) which knows enough to put 4-byte quantities on the stream!  Reader must know that size is in long words or double-bytes."
]
