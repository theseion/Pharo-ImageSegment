Extension { #name : #HandMorph }

{ #category : #'*System-Object Storage' }
HandMorph >> objectForDataStream: refStrm [
	| dp |
	"I am about to be written on an object file.  Write a path to me in the other system instead."

	(World hands includes: self) ifTrue: [^ self].
	dp := DiskProxy global: #World selector: #primaryHand args: #().
	refStrm replace: self with: dp.
	^ dp
]
