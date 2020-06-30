Extension { #name : #CompiledMethod }

{ #category : #'*System-Object Storage' }
CompiledMethod >> objectForDataStream: refStrm [
	
	self primitive = 117 ifTrue: [self literals first at: 4 put: 0].

]

{ #category : #'*System-Object Storage' }
CompiledMethod >> readDataFrom: aDataStream size: varsOnDisk [
	"Fill in my fields.  My header and number of literals are already installed.  Must read both objects for the literals and bytes for the bytecodes."

	self error: 'Must use readMethod'.
]

{ #category : #'*System-Object Storage' }
CompiledMethod >> storeDataOn: aDataStream [
	"Store myself on a DataStream.  I am a mixture of objects and raw data bytes.  Only use this for blocks.  Normal methodDictionaries should not be put out using ReferenceStreams.  Their fileOut should be attached to the beginning of the file."

	| byteLength lits |
	"No inst vars of the normal type"
	byteLength := self basicSize.
	aDataStream
		beginInstance: self class
		size: byteLength.
	lits := self numLiterals + 1.	"counting header"
	1 to: lits do:
		[:ii | aDataStream nextPut: (self objectAt: ii)].
	lits*4+1 to: byteLength do:
		[:ii | aDataStream byteStream nextPut: (self basicAt: ii)].
			"write bytes straight through to the file"
]
