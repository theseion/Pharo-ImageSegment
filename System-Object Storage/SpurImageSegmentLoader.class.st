"
SpurImageSegmentLoader is the abstract class for loaders of 32-bit and 64-bit Spur image segments.  The VM has both storing and loading primitives and the store primitive is always used.  The load primitive is used when the word size of the current system matches that of the stored segment (orf the word size of the system in which the segment was stored).  A word on encoding.  The keys in oopMap are byte positions of the start of the object, offset by the 64-bit version stamp.  So the first object, which has oop 0, is in the map at 0, and corresponds to index 3 in the segment data.

position starts at zero and readUInt32 increments position by 4 before using uint32At: to access segment.  Hence the first access via readUInt32 is of index 1 in segment data.  Later on position is reset to 8 bytes beyond the oop to access the data.

Instance Variables
	oopMap:		<Dictionary of: oop (Integer) -> object>
	outPointers:	<Array>
	position:		<Integer>
	segment:		<WordArrayForSegment>

oopMap
	- the map from the oop of an object to the object with that oop

outPointers
	- the array of imported objects, objects not in the segment but referred to by the segment

position
	- the current position when parsing the segment

segment
	- the segment data, which starts with 64-bits of version stamp, so the first object starts at index 3, and has oop 0.

"
Class {
	#name : #SpurImageSegmentLoader,
	#superclass : #Object,
	#instVars : [
		'segment',
		'outPointers',
		'oopMap',
		'position',
		'pcDependentObjects'
	],
	#classVars : [
		'TopHashBit'
	],
	#category : #'System-Object Storage'
}

{ #category : #reading }
SpurImageSegmentLoader >> allocate16BitObject: class size: nShorts [
	(class isBits and: [class isShorts]) ifFalse:
		[self error: 'shorts class expected'].
	^class basicNew: nShorts
]

{ #category : #reading }
SpurImageSegmentLoader >> allocate32BitObject: class size: nWords [
	(class isBits and: [class isWords]) ifFalse:
		[self error: 'words class expected'].
	^class basicNew: nWords
]

{ #category : #reading }
SpurImageSegmentLoader >> allocate64BitObject: class size: nLongs [
	(class isBits and: [class isLongs]) ifFalse:
		[self error: 'longs class expected'].
	^class basicNew: nLongs
]

{ #category : #reading }
SpurImageSegmentLoader >> allocate8BitObject: class size: nBytes [
	class isBytes ifFalse:
		[self error: 'bytes class expected'].
	^class basicNew: nBytes
]

{ #category : #reading }
SpurImageSegmentLoader >> allocateCompiledCode: class size: nBytes [
	"Allocate a CompiledCode object.  nBytes must be reduced
	 by the number of objects in the method (header and literals)." 
	self subclassResponsibility
]

{ #category : #reading }
SpurImageSegmentLoader >> allocateFixedAndVariableObject: class size: nSlots [
	(class isPointers and: [class isVariable]) ifFalse:
		[self error: 'variable pointers class expected'].
	^class basicNew: nSlots - class instSize
]

{ #category : #reading }
SpurImageSegmentLoader >> allocateFixedSizeObject: class size: instSize [
	(class isPointers and: [class isFixed]) ifFalse:
		[self error: 'fixed pointers class expected'].
	class instSize = instSize ifFalse: [self halt].
	^class basicNew
]

{ #category : #reading }
SpurImageSegmentLoader >> allocateObject: format classIndex: classIndex slots: numSlots [
	"Allocate an instance of the class referenced by classIndex, with the size computed from numSlots and format."
	self subclassResponsibility
]

{ #category : #reading }
SpurImageSegmentLoader >> allocateVariableSizeObject: class size: numSlots [
	(class isPointers and: [class isVariable]) ifFalse:
		[self error: 'variable pointers class expected'].
	^class basicNew: numSlots
]

{ #category : #private }
SpurImageSegmentLoader >> checkValidFormat: formatPlusRememberedBit [
	"valid formats:
		0 = 0 sized objects (UndefinedObject True False et al)
		1 = non-indexable objects with inst vars (Point et al)
		2 = indexable objects with no inst vars (Array et al)
		3 = indexable objects with inst vars (MethodContext AdditionalMethodState et al)
		4 = weak indexable objects with inst vars (WeakArray et al)
		5 = weak non-indexable objects with inst vars (ephemerons) (Ephemeron)
		6 unused, reserved for exotic pointer objects?
		7 Forwarded Object, 1st field is pointer, rest of fields are ignored
		8 unused, reserved for exotic non-pointer objects?
		9 64-bit indexable
		10 - 11 32-bit indexable	(11 unused in 32 bits)
		12 - 15 16-bit indexable	(14 & 15 unused in 32-bits)
		16 - 23 byte indexable		(20-23 unused in 32-bits)
		24 - 31 compiled method	(28-31 unused in 32-bits)"
	self assert: (formatPlusRememberedBit between: 6 and: 8) not.
	self assert: (formatPlusRememberedBit < 32
				or: [formatPlusRememberedBit = 33 "classes are non-indexable"])
]

{ #category : #private }
SpurImageSegmentLoader >> classIndexInOutPointers: classIndex [
	"If the top bit of a classIndex is set it is that of a class imported from outPointers"
	^classIndex anyMask: 16r200000
]

{ #category : #filling }
SpurImageSegmentLoader >> fillBytes: object oop: oop [
	| word |
	word := self readUint32.
	1 to: object basicSize do:
		[:i | object basicAt: i put: (word bitAnd: 16rFF).
		word := (i bitAnd: 3) = 0 
			ifTrue: [self readUint32]
			ifFalse: [word >> 8]].
	^object
]

{ #category : #filling }
SpurImageSegmentLoader >> fillCompiledCode: codeObject oop: oop [
	| header startMinusOne numBytes word |
	header := self readOop.
	1 to: codeObject numLiterals do:
		[:i | codeObject literalAt: i put: self readOop].
	startMinusOne := codeObject initialPC - 1.
	numBytes := codeObject basicSize - startMinusOne.
	word := self readUint32.
	1 to: numBytes do:
		[:i |
		 codeObject basicAt: startMinusOne + i put: (word bitAnd: 16rFF).
		 word := (i bitAnd: 3) = 0 
			ifTrue: [self readUint32]
			ifFalse: [word >> 8]].
	^codeObject
]

{ #category : #filling }
SpurImageSegmentLoader >> fillContext: ctx oop: oop [
	1 to: ctx class instSize do:
		[:i | ctx instVarAt: i put: self readOop].
	1 to: ctx stackPtr do:
		[:i | ctx basicAt: i put: self readOop].
	^ctx
]

{ #category : #filling }
SpurImageSegmentLoader >> fillObject: object oop: oop [
	"Fill the object's inst vars with data/other objects.  Remember any pc-dependent objects (contexts
	 and blocks) so that their pcs can be updated when their methods have been brought in as well."
	| class |
	"First set position to 4 bytes before the first field, in readiness to read the object's data"
	position := oop + 16. "8 bytes of version stamp  + 8 bytes of object header - 4 bytes of preincrement + 4 bytes 0->1 relative index"
	class := object class.
	class isPointers ifTrue:
		[class isVariable ifTrue:
			[object isContext ifTrue:
				[pcDependentObjects addLast: object.
				 ^self fillContext: object oop: oop].
			 object isBlock ifTrue:
				[pcDependentObjects addLast: object].
			^self fillVariablePointers: object oop: oop].
		object isBehavior ifTrue:
			[^self fillBehavior: object oop: oop].
		 ^self fillPointers: object oop: oop].
	class isBytes ifTrue:
		[object isCompiledCode ifTrue:
			[^self fillCompiledCode: object oop: oop].
		 ^self fillBytes: object oop: oop].
	class isWords ifTrue:
		[^self fillWords: object oop: oop].
	class isLongs ifTrue:
		[^self fillWords: object oop: oop].
	^self fillShorts: object oop: oop
]

{ #category : #filling }
SpurImageSegmentLoader >> fillPointers: object oop: objOop [
	1 to: object class instSize do:
		[:index|
		 object instVarAt: index put: self readOop].
	^object
]

{ #category : #filling }
SpurImageSegmentLoader >> fillVariablePointers: object oop: objOop [
	1 to: object class instSize do:
		[:index|
		 object instVarAt: index put: self readOop].
	1 to: object basicSize do:
		[:index|
		 object basicAt: index put: self readOop].
	^object
]

{ #category : #reading }
SpurImageSegmentLoader >> fillWords: object oop: oop [
	| size |
	size := object basicSize.
	(size = 2 and: [object isFloat])
		ifTrue: "boxed floats are in platform order internally (hence in platform order in the segment) but in big-endian order externally"
			[object
				basicAt: 2 put: self readUint32;
				basicAt: 1 put: self readUint32]
		ifFalse:
			[1 to: object basicSize do:
				[:i |
				 object basicAt: i put: self readUint32]].
	^object
]

{ #category : #filling }
SpurImageSegmentLoader >> ignoringAccessToWordAfterSegmentDo: aBlock [
	"Both fillBytes:oop: and fillShorts:oop: may read an extra word beyond the end of data.
	 If the object is the last in the segment this will cause an out-of-bounds error.
	 Squash this error."
	^aBlock
		on: Error "Why do we still not have SubscriptOutOfBounds or some such??"
		do: [:ex|
			ex messageText = ('subscript is out of bounds: ', (segment size + 1) printString) ifFalse:
				[ex pass].
			ex
				searchFrom: (ex signalerContext findContextSuchThat: [:ctxt| ctxt selector == #uint32At:]);
				resumeUnchecked: 0]
]

{ #category : #loading }
SpurImageSegmentLoader >> loadSegmentFrom: segmentWordArray outPointers: outPointerArray [
	| version end memory |
	segment := segmentWordArray.
	outPointers := outPointerArray.
	position := 0.
	version := self readUint32.
	(self validImageSegmentVersion: (version bitAnd: 16rFFFFFF)) ifFalse:
		[^self error: 'Cannot read this segment (endianness?)'].
	"First allocate all objects, then fill in their fields via oopMap"
	memory := OrderedCollection new: 1000.
	oopMap := Dictionary new.
	pcDependentObjects := OrderedCollection new.
	end := segment size * 4.
	position := 8.
	[position < end] whileTrue:
		[memory addLast: self readObject].
	self ignoringAccessToWordAfterSegmentDo:
		[oopMap keysAndValuesDo:
			[:oop :obj | self fillObject: obj oop: oop]].
	self updatePCDependentObjects.
	"Answer list of all objects (unlike primitive, which returned the first object and relied on other objects being consecutive in memory)"
	^memory
]

{ #category : #private }
SpurImageSegmentLoader >> oopIndexForClassIndex: classIndex [
	"When a classIndex doesn't have the topBit set it maps to an oop in the segment thusly:"
	^classIndex - 16 "self firstClassIndexPun" * 8 "self allocationUnit"
]

{ #category : #private }
SpurImageSegmentLoader >> outPointerIndexForClassIndex: classIndex [
	"If the top bit of a classIndex is set it is that of a class imported from outPointers"
	^classIndex - 16r1FFFFF "a.k.a. classIndex - 16r200000 + 1"
]

{ #category : #reading }
SpurImageSegmentLoader >> readObject [
	"Read the header and the class of the object, instantiate it, and store it in oopMap at its oop."
	self subclassResponsibility
]

{ #category : #reading }
SpurImageSegmentLoader >> readOop [
	"Read an oop and map it to an object:
		- The oop may be immediate in which case its tag indicates its class and the remeaining bits its value.
		- the oop may have its top bit set in which case it is an index into the outPointers
		- otherwise the oop is a byte offset from the start of the first object in the segment and is in oopMap."
	self subclassResponsibility
]

{ #category : #reading }
SpurImageSegmentLoader >> readUint32 [
	^segment at: (position := position + 4) // 4
]

{ #category : #filling }
SpurImageSegmentLoader >> updatePCDependentObjects [
	pcDependentObjects do:
		[:contextOrBlock|

		contextOrBlock isContext ifTrue:
			[contextOrBlock pc ifNotNil:
				[:pc| contextOrBlock pc: (self mapPC: pc in: contextOrBlock method)]].

		(contextOrBlock isBlock
		 and: [contextOrBlock isFullBlock not])ifTrue:
			[contextOrBlock instVarNamed: 'startpc' put: (self mapPC: contextOrBlock startpc in: contextOrBlock method)]]
]

{ #category : #private }
SpurImageSegmentLoader >> validImageSegmentVersion: threeByteInteger [
	self subclassResponsibility
]
