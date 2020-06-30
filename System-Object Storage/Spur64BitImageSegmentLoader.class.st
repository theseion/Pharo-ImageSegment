Class {
	#name : #Spur64BitImageSegmentLoader,
	#superclass : #SpurImageSegmentLoader,
	#category : #'System-Object Storage'
}

{ #category : #reading }
Spur64BitImageSegmentLoader >> allocateCompiledCode: class size: nBytes [
	"Allocate a CompiledCode object.  nBytes must be reduced
	 by the number of objects in the method (header and literals)." 
	| header delta |
	class isCompiledMethodClass ifFalse:
		[self error: 'compiled code class expected'].
	header := self readOop.
	delta := (header bitAnd: 32767) + 1 * 8.
	^class newMethod: nBytes - delta header: header
]

{ #category : #reading }
Spur64BitImageSegmentLoader >> allocateObject: format classIndex: classIndex slots: numSlots [
	"Allocate an instance of the class referenced by classIndex, with the size computed from numSlots and format."
	| class |
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
		 nBytes := numSlots * 8 - (format bitAnd: 7).
		 format >= 24 ifTrue:
			[^self allocateCompiledCode: class size: nBytes].
		 ^self allocate8BitObject: class size: nBytes].
	format >= 12 ifTrue:
		[| nShorts |
		 nShorts := numSlots * 4 - (format bitAnd: 3).
		 ^self allocate16BitObject: class size: nShorts].
	format >= 10 ifTrue:
		[| nWords |
		 nWords := numSlots * 2 - (format bitAnd: 1).
		 ^self allocate32BitObject: class size: nWords].
	format = 9 ifTrue:
		[^self allocate64BitObject: class size: numSlots].
	format = 33 ifTrue:
		[^self allocateAndPartFillClassObject: class size: numSlots].
	self error: 'Unknown object format'
]

{ #category : #private }
Spur64BitImageSegmentLoader >> mapPC: pc in: compiledCode [
	"Assuming the word size of compiledCode is 4, and that the pc is one for a word size of 8,
	 map the pc from 8 to 4 byte literals. The filter is in updatePCDependentObjects."
	^pc - (compiledCode numLiterals + 1 * 4)
]

{ #category : #reading }
Spur64BitImageSegmentLoader >> readObject [
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
			ensure: "Spur objects have at least one slot"
				[position := oop + 16 + ((numSlots max: 1) * 8)]
]

{ #category : #reading }
Spur64BitImageSegmentLoader >> readOop [
	"Read an oop and map it to an object:
		- The oop may be immediate in which case its tag indicates its class and the remeaining bits its value.
		- the oop may have its top bit set in which case it is an index into the outPointers
		- otherwise the oop is a byte offset from the start of the first object in the segment and is in oopMap.
	 The method is written to avoid large integer arithmetic as much as possible."
	| lo hi topBit oop |
	lo := self readUint32.
	hi := self readUint32.
	topBit := hi bitShift: -31.
	^(lo bitAnd: 7) caseOf: {
		[0]	->	[topBit = 1
					ifTrue:
						[oop := (hi - 16r80000000 bitShift: 32) + lo.
						 outPointers at: oop / 8 + 1]
					ifFalse:
						[oop := (hi bitShift: 32) + lo.
						 oopMap at: oop]].
		[1] ->	[(lo bitShift: -3) bitOr: (hi - (topBit = 1 ifTrue: [16r100000000] ifFalse: [0]) bitShift: 29)].
		[2] ->	[Character value: ((lo bitShift: -3) bitOr: (hi bitShift: 29))].
		[4] ->	[(hi = 0 and: [lo <= 15]) "+ve & -ve zero"
					ifTrue: [lo <= 7 ifTrue: [0.0] ifFalse: [-0.0]]
					ifFalse: "convert lo: | tag | sign | mantissa low 28 bits | hi: | mantissa high 24 bits | exponent - 896 |
							to hi: | mantissa high 20 bits | exponent 11 bits | sign | lo: | mantissa low 32 bits |"
						[(BoxedFloat64 basicNew: 2)
								basicAt: 1 put: ((lo bitAnd: 8) bitShift: 28) + ((hi bitShift: -4) + (896 bitShift: 20));
								basicAt: 2 put: (lo bitShift: -4) + ((hi bitAnd: 15) bitShift: 28);
							* 1.0 "& reduce to SmallFloat64 if possible"]]}
		otherwise: [self error: 'unrecognized tag pattern']
]

{ #category : #filling }
Spur64BitImageSegmentLoader >> updatePCDependentObjects [
	Smalltalk wordSize ~= 8 ifTrue:
		[super updatePCDependentObjects]
]

{ #category : #private }
Spur64BitImageSegmentLoader >> validImageSegmentVersion: threeByteInteger [
	^threeByteInteger = 68021
]
