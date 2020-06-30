Extension { #name : #Class }

{ #category : #'*System-Object Storage' }
Class >> objectForDataStream: refStrm [
	"I am about to be written on an object file.  Write a reference to a class in Smalltalk instead."

	refStrm insideASegment
		ifFalse: [ "Normal use"
			^ DiskProxy
				global: self instanceSide name
				selector: #withClassVersion:
				args: {self classVersion} ]
		ifTrue: [ "recording objects to go into an ImageSegment"
			(refStrm rootObject includes: self)
				ifTrue: [ ^ self ].
			"is in roots, intensionally write out, ^ self"

			"A normal class.  remove it from references.  Do not trace."
			refStrm references removeKey: self ifAbsent: [  ].	"already there"
			^ nil ]
]

{ #category : #'*System-Object Storage' }
Class >> storeDataOn: aDataStream [
	"I don't get stored.  Use a DiskProxy"


	self error: 'use a DiskProxy to store a Class'
]

{ #category : #'*System-Object Storage' }
Class >> withClassVersion: aVersion [
	aVersion = self classVersion ifTrue:[^self].
	^self error: 'Invalid class version'
]
