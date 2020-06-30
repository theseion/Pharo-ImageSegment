Extension { #name : #Character }

{ #category : #'*System-Object Storage' }
Character >> objectForDataStream: refStrm [
	"I am being collected for inclusion in a segment.  Do not include Characters!  Let them be in outPointers."

	refStrm insideASegment
		ifFalse: ["Normal use" ^ self]
		ifTrue: ["recording objects to go into an ImageSegment"			
			"remove it from references.  Do not trace."
			refStrm references removeKey: self ifAbsent: [].
			^ nil]

]

{ #category : #'*System-Object Storage' }
Character class >> readImmediateFrom: aDataStream size: varsOnDisk [
	"Read an instance of self based on the contents of aDataStream.  Return it.
	 Read in the value as written by Character>>storeDataOn:.
	 NOTE: This method must send beginReference: before reading any objects from aDataStream that might reference it. Because we need to read the value before creating the object, we need to reset the current reference position."
	| refPosn instance |
	refPosn := aDataStream getCurrentReference.
	instance := self value: aDataStream next.
	aDataStream setCurrentReference: refPosn.
	aDataStream beginReference: instance.
	^instance
]
