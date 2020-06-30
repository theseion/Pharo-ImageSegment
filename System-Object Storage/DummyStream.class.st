"
The purpose of this class is to absorb all stream messages and do nothing.  This is so ReferenceStream can pretend to write on it while traversing all objects it would normally write.  We need to know what those object are.  8/17/96 tk

"
Class {
	#name : #DummyStream,
	#superclass : #Stream,
	#category : #'System-Object Storage'
}

{ #category : #'instance creation' }
DummyStream class >> on: aFile [
	"Return a new DummyStream instance, ignoring the argument."

	^ self basicNew

]

{ #category : #protocol }
DummyStream >> binary [
	"do nothing"
]

{ #category : #'open/close' }
DummyStream >> close [
	"do nothing"
]

{ #category : #accessing }
DummyStream >> next: anInteger putAll: aCollection startingAt: anInteger3 [ 

	^aCollection
]

{ #category : #accessing }
DummyStream >> nextInt32Put: arg [
	"do nothing"
]

{ #category : #accessing }
DummyStream >> nextNumber: cnt put: num [
	"do nothing"
]

{ #category : #accessing }
DummyStream >> nextPut: aByte [
	"do nothing"
	^aByte
]

{ #category : #accessing }
DummyStream >> nextPutAll: aByteArray [
	"do nothing"
	
	^aByteArray
]

{ #category : #accessing }
DummyStream >> nextStringPut: aString [
	"do nothing"
	^aString
]

{ #category : #accessing }
DummyStream >> originalContents [

	^ ''
]

{ #category : #accessing }
DummyStream >> position [
	"Return any random number.  Here is where the real lying begins.  We are a DummyStream afterall.  8/17/96 tk"

	^ 47 
]

{ #category : #accessing }
DummyStream >> position: anOffset [
	"Pretend to position wherever the caller says!"

]

{ #category : #positioning }
DummyStream >> skip: aNumber [
	"Do nothing."
]

{ #category : #'error handling' }
DummyStream >> subclassResponsibility [
	"Do nothing.  Most messages to class Stream are defined as subclassResponsibility.  Just accept them.  8/17/96 tk"

	"No error.  Just go on."
]
