Extension { #name : #Behavior }

{ #category : #'*System-Object Storage' }
Behavior >> rootStubInImageSegment: imageSegment [ 

	^ ImageSegmentRootStub new
		xxSuperclass: superclass
		format: format
		segment: imageSegment
]

{ #category : #'*System-Object Storage' }
Behavior >> startUpFrom: anObject [
	"Override this when a per-instance startUp message needs to be sent.  For example, to correct the order of 16-bit non-pointer data when it came from a different endian machine. This can happens with ImageSegment for example."

	^ nil
]
