Extension { #name : #Process }

{ #category : #'*System-Object Storage' }
Process >> objectForDataStream: refStrm [
	"I am not allowed to be written on an object file."

	refStrm replace: self with: nil.
	^ nil
]
