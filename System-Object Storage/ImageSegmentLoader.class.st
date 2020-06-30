"
This class is used to load objects from an ImageSegment that is incompatible with the current VM (see LegacyImageSegment>>loadSegmentFrom:outPointers:).
"
Class {
	#name : #ImageSegmentLoader,
	#superclass : #Object,
	#instVars : [
		'segment',
		'outPointers',
		'oopMap',
		'position'
	],
	#classVars : [
		'BytesInHeader',
		'CompactClasses',
		'HeaderTypeClass',
		'HeaderTypeFree',
		'HeaderTypeMask',
		'HeaderTypeShort',
		'HeaderTypeSizeAndClass'
	],
	#category : #'System-Object Storage'
}

{ #category : #'class initialization' }
ImageSegmentLoader class >> initialize [
	HeaderTypeMask := 3.
	HeaderTypeSizeAndClass := 0.	"3-word header"
	HeaderTypeClass := 1.				"2-word header"
	HeaderTypeFree := 2.					"free block"
	HeaderTypeShort := 3.				"1-word header"
	BytesInHeader := {
		HeaderTypeSizeAndClass -> 12.
		HeaderTypeClass -> 8.
		HeaderTypeShort -> 4.
	} as: Dictionary.
	"explicit list in case image has no/different compact classes"
	CompactClasses := {CompiledMethod. nil. Array. LargeNegativeInteger.
		LargePositiveInteger. Float. MethodDictionary. Association.
		Point. Rectangle. ByteString. BlockClosure.
		nil "was BlockCOntext; needs special handling". Context. nil. Bitmap. 
		nil. nil. nil. nil. nil. nil. nil. nil. nil. nil. nil. nil. nil. nil. nil}.

]

{ #category : #allocating }
ImageSegmentLoader >> allocateBlockContext: nWords [
	"not supported in Spur - nil is fine for Etoys projects"
	^nil
	"| homeOop methodOop method |
	homeOop := self uint32At: position + 24.
	methodOop := self uint32At: homeOop + 16.
	method := self readObjectAt: methodOop.
	^BlockContext newForMethod: method"
]

{ #category : #allocating }
ImageSegmentLoader >> allocateBytesObject: classOop size: nBytes [
	| class |
	class := self fetchClass: classOop.
	class isBytes ifFalse:
		[self error: 'bytes class expected'].
	^class basicNew: nBytes
]

{ #category : #allocating }
ImageSegmentLoader >> allocateCompiledMethod: nBytes [
	"CompiledMethods need special handling:
	- the method header bits changed
	- the primitive is now the first 3 bytecodes
	- the trailer encoding changed, too
	Here we calculate the new size needed after adding
	the primitive byte codes, stripping the old trailer and
	adding one byte for the NoTrailer code."
	| header numLits bytecodes lastByte trailerBytes |
	header := self mapOop: (self uint32At: position + 4).
	header := self mapToSpurHeader: header.
	numLits := header bitAnd: 16rFF.
	bytecodes := nBytes - (1 + numLits * 4). "subtract header and literals"
	lastByte := self uint8At: position + nBytes.
	trailerBytes := lastByte = 0 ifTrue: "up to four 0 bytes"
		[(self uint8At: position + nBytes - 1) = 0 ifFalse: [1] ifTrue:
			[(self uint8At: position + nBytes - 2) = 0 ifFalse: [2] ifTrue:
				[(self uint8At: position + nBytes - 3) = 0 ifFalse: [3] ifTrue: [4]]]] ifFalse:
		[lastByte < 252 ifTrue:
			[lastByte + 1 "Magic sources (tempnames encoded in last bytes)"] ifFalse:
			[4 "Normal 4-byte source pointer"]].
	"subtract old trailer, add 1 byte for new trailer"
	bytecodes := (bytecodes - trailerBytes max: 0) + 1.
	"add 3 bytes for prim call"
	(header bitAnd: 16r10000) > 0 ifTrue: [bytecodes := bytecodes + 3].
	^CompiledMethod newMethod: bytecodes header: header
]

{ #category : #allocating }
ImageSegmentLoader >> allocateFixedAndVariableObject: classOop size: nWords [
	| class |
	classOop = 13 ifTrue:
		[^self allocateBlockContext: nWords].
	classOop = 14 ifTrue:
		[^self allocateMethodContext: nWords].
	class := self fetchClass: classOop.
	(class isPointers and: [class isVariable]) ifFalse:
		[self error: 'variable pointers class expected'].
	^class basicNew: nWords - class instSize
]

{ #category : #allocating }
ImageSegmentLoader >> allocateFixedSizeObject: classOop size: nWords [
	| class |
	class := self fetchClass: classOop.
	(class isPointers and: [class isFixed]) ifFalse:
		[self error: 'fixed pointers class expected'].
	class instSize = nWords ifFalse: [self halt].
	^class basicNew
]

{ #category : #allocating }
ImageSegmentLoader >> allocateMethodContext: nWords [
	"not supported in Spur - nil is fine for Etoys projects"
	^nil
	"| methodOop method |
	methodOop := self uint32At: position + 16.
	method := self readObjectAt: methodOop.
	^Context newForMethod: method"
]

{ #category : #allocating }
ImageSegmentLoader >> allocateObject: format class: class size: nWords [
	| nBytes |
	format <= 1 ifTrue:
		[^self allocateFixedSizeObject: class size: nWords].
	format = 2 ifTrue:
		[^self allocateVariableSizeObject: class size: nWords].
	(format between: 3 and: 4) ifTrue:
		[^self allocateFixedAndVariableObject: class size: nWords].
	format = 6 ifTrue:
		[^self allocateWordsObject: class size: nWords].
	nBytes :=  (nWords * 4) - (format bitAnd: 3).
	format >= 12 ifTrue:
		[^self allocateCompiledMethod: nBytes].
	format >= 8 ifTrue:
		[^self allocateBytesObject: class size: nBytes].
	self error: 'Unknown object format'.

]

{ #category : #allocating }
ImageSegmentLoader >> allocateVariableSizeObject: classOop size: nWords [
	| class |
	class := self fetchClass: classOop.
	(class isPointers and: [class isVariable]) ifFalse:
		[self error: 'variable pointers class expected'].
	^class basicNew: nWords
]

{ #category : #allocating }
ImageSegmentLoader >> allocateWordsObject: classOop size: nWords [
	| class |
	class := self fetchClass: classOop.
	class == Float ifTrue: [class := BoxedFloat64].
	(class isBits and: [class isWords]) ifFalse:
		[self error: 'words class expected'].
	^class basicNew: nWords
]

{ #category : #reading }
ImageSegmentLoader >> fetchClass: classOop [
	| index class superclass format |
	classOop < 32 ifTrue:
		[^CompactClasses at: classOop].
	(index := classOop >> 2) >= 16r20000000 ifTrue:
		[^outPointers at: index - 16r20000000].
	"class is in segment ... load it out-of-order"
	superclass := self fetchClass: (self uint32At: classOop + 4).
	format := self mapOop: (self uint32At: classOop + 12).
	format := self mapToSpurFormat: format.
	class := self readObjectAt: classOop.
	class superclass: superclass
		methodDictionary: MethodDictionary new
		format: format.
	class flushCache.
	^class
]

{ #category : #filling }
ImageSegmentLoader >> fillBehavior: class oop: oop [
	position := oop.
	class superclass: (self mapOop: self readUint32).
	class methodDict: (self mapOop: self readUint32).
	class setFormat: (self mapToSpurFormat: (self mapOop: self readUint32)).
	4 to: class class instSize do:
		[:i | class instVarAt: i put: (self mapOop: self readUint32)].
	class flushCache.
	^class
]

{ #category : #filling }
ImageSegmentLoader >> fillBytes: object oop: oop [
	| word |
	position := oop.
	"Guard against a bad read ahead that is effectively a noop
	but can happen with e.g. an empty string at the last position in
	the segment"
	object basicSize = 0 ifTrue: [ ^ self ].
	
	word := self readUint32.
	1 to: object basicSize do:
		[:i | object basicAt: i put: (word bitAnd: 16rFF).
		word := (i bitAnd: 3) = 0 
			ifTrue: [
				"Guard against a bad read ahead that is effectively a noop
				but can happen with e.g. a string at the last position in
				the segment"
				[ self readUint32 ]
					on: SubscriptOutOfBounds
					do: [ :ex |
						(i = object basicSize and: [
							 oop = oopMap keys sort last ]) ifFalse: [
							ex pass ] ] ]
			ifFalse: [word >> 8]].

]

{ #category : #filling }
ImageSegmentLoader >> fillCompiledMethod: method oop: oop [
	"The method header was already mapped to Spur format.
	Here we just insert the bytecode for calling a primitive.
	The last byte is left at 0 to indicate no trailer."
	| header start size prim word |
	position := oop.
	header := self mapOop: self readUint32.
	1 to: method numLiterals do:
		[:i | method literalAt: i put: (self mapOop: self readUint32)].
	start := method initialPC - 1.
	size := method basicSize - start - 1.	"subtract 1 byte for empty trailer"
	(method header anyMask: 65536) ifTrue: "add primitive call"
		[prim := self mapToSpurPrim: header.
		method basicAt: start + 1 put: 16r8B.
		method basicAt: start + 2 put: prim \\ 256.
		method basicAt: start + 3 put: prim // 256.
		start := start + 3.
		size := size - 3].
	word := self readUint32.
	1 to: size do:
		[:i | method basicAt: start + i put: (word bitAnd: 16rFF).
		word := (i bitAnd: 3) = 0 
			ifTrue: [self readUint32]
			ifFalse: [word >> 8]].

]

{ #category : #filling }
ImageSegmentLoader >> fillContext: ctx oop: oop [
	position := oop.
	1 to: ctx class instSize do:
		[:i | ctx instVarAt: i put: (self mapOop: self readUint32)].
	1 to: ctx stackPtr do:
		[:i | ctx basicAt: i put: (self mapOop: self readUint32)].
	^ctx
]

{ #category : #filling }
ImageSegmentLoader >> fillObject: object oop: oop [
	object isBehavior ifTrue:
		[^self fillBehavior: object oop: oop].
	object isContext ifTrue:
		[^self fillContext: object oop: oop].
	object class isPointers ifTrue:
		[^self fillPointers: object oop: oop].
	object isCompiledMethod ifTrue:
		[^self fillCompiledMethod: object oop: oop].
	object class isBytes ifTrue:
		[^self fillBytes: object oop: oop].
	^self fillWords: object oop: oop


]

{ #category : #filling }
ImageSegmentLoader >> fillPointers: object oop: oop [
	position := oop.
	1 to: object class instSize do:
		[:i | object instVarAt: i put: (self mapOop: self readUint32)].
	1 to: object basicSize do:
		[:i | object basicAt: i put: (self mapOop: self readUint32)].
	^object
]

{ #category : #filling }
ImageSegmentLoader >> fillWords: object oop: oop [
	position := oop.
	1 to: object basicSize do:
		[:i | object basicAt: i put: self readUint32].

]

{ #category : #loading }
ImageSegmentLoader >> loadSegmentFrom: segmentWordArray outPointers: outPointerArray [
	| version end memory |
	segment := segmentWordArray.
	outPointers := outPointerArray.
	position := 0.
	version := self readUint32.
	(#(6502 6504) includes: (version bitAnd: 16rFFFF)) ifFalse:
		[^self error: 'Cannot read this segment (endianness?)'].
	"First allocate all objects, then fill in their fields via oopMap"
	memory := OrderedCollection new: 1000.
	oopMap := Dictionary new.
	end := segment size * 4.
	[position < end] whileTrue:
		[memory add: self readObject].
	oopMap keysAndValuesDo:
		[:oop :obj | self fillObject: obj oop: oop].
	"Return list of all objects (unlike primitive, which returned the first object and relied on other objects being consecutive in memory)"
	^memory
]

{ #category : #reading }
ImageSegmentLoader >> mapOop: oop [
	| i |
	(oop bitAnd: 1) = 0 ifTrue:	"pointer"
		[(i := oop >> 2) >= 16r20000000 ifTrue:
			[^outPointers at: i - 16r20000000].
		^oopMap at: oop].
	i := oop >> 1.	"signed small int"
	i <= 16r3FFFFFFF ifTrue: [^i].
	^i - 16r80000000
]

{ #category : #reading }
ImageSegmentLoader >> mapToSpurFormat: format [
	| instSpec instSize |
	instSpec := format >> 7 bitAnd: 16r0F.
	instSize := (format >> 10 bitAnd: 16rC0) + (format >> 1 bitAnd: 16r3F) - 1.
	instSpec := instSpec <= 4
		ifTrue: [instSpec]	"no change"
		ifFalse: [instSpec = 6
			ifTrue: [10]	"WordArray was 6 now 10-11"
			ifFalse: [instSpec >= 12
				ifTrue: [instSpec + 12]	"CompiledMethods 12-15 now 24-31"
				ifFalse: [instSpec >= 8
					ifTrue: [instSpec + 8]	"CompiledMethods 8-11 now 16-23"	
					ifFalse: [self error: 'unexpected format']]]].
	^instSpec << 16 + instSize
]

{ #category : #reading }
ImageSegmentLoader >> mapToSpurHeader: header [
	"Keep numLits, numArgs, and largeFrame bits, move numLits, set primitive flag"
	| primFlag numLits |
	primFlag := (header bitAnd: 16r100001FF) > 0 ifTrue: [16r10000] ifFalse: [0].
	numLits := header >> 9 bitAnd: 16rFF.
	^(header bitAnd: 16r0FFE0000) + primFlag + numLits

]

{ #category : #reading }
ImageSegmentLoader >> mapToSpurPrim: header [
	| primBits |
	primBits := header bitAnd: 16r100001FF.
	^(primBits bitAnd: 16r1FF) + (primBits bitShift: -19)
]

{ #category : #reading }
ImageSegmentLoader >> readObject [
	| header oop nWords class format |
	header := self readUint32.
	(header bitAnd: HeaderTypeMask) caseOf: {
		[HeaderTypeSizeAndClass] ->
			[nWords := header >> 2. class := self readUint32. header := self readUint32].
		[HeaderTypeClass] ->
			[class := header - 1. header := self readUint32. nWords := header >> 2 bitAnd: 63].
		[HeaderTypeShort] ->
			[nWords := header >> 2 bitAnd: 63. class := header >> 12 bitAnd: 31].
	} otherwise: [self error: 'unexpected free chunk'].
	nWords := nWords - 1.	"nWords includes 1 header word"
	oop := position.
	^[oopMap at: oop ifAbsentPut:
		[format := header >> 8 bitAnd: 15.
		"hash := header >> 17 bitAnd: 4095."
		self allocateObject: format class: class size: nWords]]
			ensure: [position := oop + (nWords * 4)]



]

{ #category : #reading }
ImageSegmentLoader >> readObjectAt: oop [
	| headerType oldPos |
	oopMap at: oop ifPresent: [:obj | ^obj].
	headerType := (self uint32At: oop) bitAnd: HeaderTypeMask.
	oldPos := position.
	position := oop - (BytesInHeader at: headerType).
	^[self readObject] ensure: [position := oldPos]
]

{ #category : #reading }
ImageSegmentLoader >> readUint32 [
	^self uint32At: (position := position + 4)
]

{ #category : #reading }
ImageSegmentLoader >> uint32At: addr [
	"TODO: do endian conversion here"
	^segment at: addr // 4
]

{ #category : #reading }
ImageSegmentLoader >> uint8At: addr [
	"TODO: do endian conversion here"
	| word |
	word := segment at: addr + 3 // 4.
	^word >> (8 * (addr + 3 \\ 4)) bitAnd: 16rFF.
]
