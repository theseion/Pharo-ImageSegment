Class {
	#name : #Spur32BitImageSegmentLoader,
	#superclass : #SpurImageSegmentLoader,
	#instVars : [
		'rangeMappings'
	],
	#category : #'System-Object Storage'
}

{ #category : #reading }
Spur32BitImageSegmentLoader >> allocateCompiledCode: class size: nBytes [
	"Allocate a CompiledCode object.  nBytes must be reduced
	 by the number of objects in the method (header and literals)." 
	| header delta |
	class isCompiledMethodClass ifFalse:
		[self error: 'compiled code class expected'].
	header := self readOop.
	delta := (header bitAnd: 32767) + 1 * 4.
	^class newMethod: nBytes - delta header: header
]

{ #category : #reading }
Spur32BitImageSegmentLoader >> allocateObject: format classIndex: classIndex slots: numSlots [
	"Allocate an instance of the class referenced by classIndex, with the size computed from numSlots and format."
	| class obj |
	class := (self classIndexInOutPointers: classIndex)
				ifTrue: [outPointers at: (self outPointerIndexForClassIndex: classIndex)]
				ifFalse: [oopMap at: (self oopIndexForClassIndex: classIndex)].
	(format <= 1 or: [format = 5"ephemerons"]) ifTrue:
		[^self allocateFixedSizeObject: class size: numSlots].
	format = 2 ifTrue:
		[^self allocateVariableSizeObject: class size: numSlots].
	(format between: 3 and: 4) ifTrue:
		[^self allocateFixedAndVariableObject: class size: numSlots].
	format >= 16 ifTrue:
		[| nBytes |
		 nBytes := numSlots * 4 - (format bitAnd: 3).
		 format >= 24 ifTrue:
			[^self allocateCompiledCode: class size: nBytes].
		 obj := self allocate8BitObject: class size: nBytes.
		 (nBytes <= 8 and: [obj isInteger and: [rangeMappings notNil]]) ifTrue:
			[rangeMappings addLast: obj].
		 ^obj].
	format >= 12 ifTrue:
		[| nShorts |
		 nShorts := numSlots * 2 - (format bitAnd: 1).
		 ^self allocate16BitObject: class size: nShorts].
	format >= 10 ifTrue:
		[obj := self allocate32BitObject: class size: numSlots.
		 (numSlots = 2 and: [obj isFloat and: [rangeMappings notNil]]) ifTrue:
			[rangeMappings addLast: obj].
		 ^obj].
	format = 9 ifTrue:
		[^self allocate64BitObject: class size: numSlots * 2].
	format = 33 ifTrue:
		[^self allocateAndPartFillClassObject: class size: numSlots].
	self error: 'Unknown object format'
]

{ #category : #loading }
Spur32BitImageSegmentLoader >> loadSegmentFrom: segmentWordArray outPointers: outPointerArray [
	"Override to initialize rangeMappings if loading a 32-bit segment into a 64-bit system"

	| result |
	Smalltalk wordSize = 8 ifTrue:
		[rangeMappings := OrderedCollection new].
	result := super loadSegmentFrom: segmentWordArray outPointers: outPointerArray.
	self maybeMapRanges.
	^result
]

{ #category : #private }
Spur32BitImageSegmentLoader >> mapPC: pc in: compiledCode [
	"Assuming the word size of compiledCode is 8, and that the pc is one for a word size of 4,
	 map the pc from 4 to 8 byte literals. The filter is in updatePCDependentObjects."
	^pc + (compiledCode numLiterals + 1 * 4)
]

{ #category : #private }
Spur32BitImageSegmentLoader >> maybeMapRanges [
	"If loading a 32-bit segment into a 64-bit segment then map LargePositiveIntegers or BoxedFloat64
	 instances that can be expressed as SmallInteger or SmallFloat64 immediates respectively.
	 Implement as a bulk become for speed."

	| ins outs |
	rangeMappings ifNil: [^self].
	ins := WriteStream on: (Array new: rangeMappings size).
	outs := WriteStream on: (Array new: rangeMappings size).
	rangeMappings do:
		[:numeric| | mapping |
		(numeric isInteger
			ifTrue:
				[mapping := numeric normalize.
				 mapping ~~ numeric]
			ifFalse:
				[mapping := numeric * 1.0.
				 mapping class ~~ numeric class]) ifTrue:
			[ins nextPut: numeric.
			 outs nextPut: mapping]].
	ins position > 0 ifTrue:
		[ins contents elementsForwardIdentityTo: outs contents copyHash: false]
]

{ #category : #reading }
Spur32BitImageSegmentLoader >> readObject [
	"Read the header and the class of the object, instantiate it, and store it in oopMap at its oop."
	| headerLo headerHi oop numSlots classIndex format rawNumSlots |
	"the oop is the address of the two byte header (which follows the overflow size word, if there is one)."
	oop := position - 8. "compensate for 64-bit version stamp"
	headerLo := self readUint32.
	headerHi := self readUint32.
	rawNumSlots := headerHi bitShift: -24.
	rawNumSlots = 255
		ifTrue: "128-bit header; overflow slots in least significant 32 bits of first 64-bit header word"
			[numSlots := headerLo.
			 oop := position - 8. "compensate for 64-bit version stamp"
			 headerLo := self readUint32.
			 headerHi := self readUint32]
		ifFalse: "64-bit header"
			[numSlots := rawNumSlots].
	"N.B. The format field is a 5 bit field, but immediately above it is the
	 remembered bit which is used to mark classes is the segment."
	self checkValidFormat: (format := (headerLo bitShift: -24) bitAnd: 63).
	classIndex := headerLo bitAnd: 16r3FFFFF.
	^[oopMap at: oop ifAbsentPut:
		[self allocateObject: format classIndex: classIndex slots: numSlots]]
			ensure: "Spur objects have at least one slot and are rounded up to a multiple of 64-bits/8 bytes in length"
				[position := oop + 16 + ((numSlots max: 1) + 1 // 2 * 8)]
]

{ #category : #reading }
Spur32BitImageSegmentLoader >> readOop [
	"Read an oop and map it to an object:
		- The oop may be immediate in which case its tag indicates its class and the remeaining bits its value.
		- the oop may have its top bit set in which case it is an index into the outPointers
		- otherwise the oop is a byte offset from the start of the first object in the segment and is in oopMap"
	| oop topBit |
	oop := self readUint32.
	topBit := oop bitShift: -31.
	^(oop bitAnd: 3) caseOf: {
		[0]	->	[topBit = 1
					ifTrue: [outPointers at: oop - 16r80000000 / 4 + 1]
					ifFalse: [oopMap at: oop]].
		[1] ->	[(oop bitShift: -1) - (topBit = 1 ifTrue: [16r80000000] ifFalse: [0])].
		[3] ->	[(oop bitShift: -1) - (topBit = 1 ifTrue: [16r80000000] ifFalse: [0])].
		[2] ->	[Character value: (oop bitShift: -2)]}
]

{ #category : #reading }
Spur32BitImageSegmentLoader >> updatePCDependentObjects [
	Smalltalk wordSize ~= 4 ifTrue:
		[super updatePCDependentObjects]
]

{ #category : #private }
Spur32BitImageSegmentLoader >> validImageSegmentVersion: threeByteInteger [
	^threeByteInteger = 6521
]
