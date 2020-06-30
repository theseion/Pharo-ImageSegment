Extension { #name : #XMLOrderPreservingDictionary }

{ #category : #'*System-Object Storage' }
XMLOrderPreservingDictionary >> rehash [
	"Smalltalk rehash."
	| newSelf |
	newSelf := self species new: self size.
	"We need to use the super implementation of here
	because this version will perform dictionary access
	to retrieve the associations, which won't work if the
	dictionary isn't properly hashed."
	super associationsDo: [ :each | newSelf noCheckAdd: each ].
	array := newSelf array
]
