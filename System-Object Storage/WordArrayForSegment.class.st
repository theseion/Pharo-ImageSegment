Class {
	#name : #WordArrayForSegment,
	#superclass : #WordArray,
	#type : #words,
	#category : #'System-Object Storage'
}

{ #category : #'instance creation' }
WordArrayForSegment class >> newFromStream: s [
	"Only meant for my subclasses that are raw bits and word-like.  For quick unpack form the disk."
	| len |

	s next = 16r80 ifTrue:
		["A compressed format.  Could copy what BitMap does, or use a 
		special sound compression format.  Callers normally compress their own way."
		^ self error: 'not implemented'].
	s skip: -1.
	len := s nextInt32.
	^ s nextWordsInto: (self basicNew: len)
]

{ #category : #'as yet unclassified' }
WordArrayForSegment >> restoreEndianness [
	"This word object was just read in from a stream.  Do not correct the Endianness because the load primitive will reverse bytes as needed."

	"^ self"

]

{ #category : #'as yet unclassified' }
WordArrayForSegment >> writeOn: aByteStream [
	"Write quickly and disregard the endianness of the words.  Store the array of bits onto the argument, aStream.  (leading byte ~= 16r80) identifies this as raw bits (uncompressed)."

	aByteStream nextInt32Put: self size.	"4 bytes"
	aByteStream nextPutAll: self

]
