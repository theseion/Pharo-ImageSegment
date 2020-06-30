Extension { #name : #Metaclass }

{ #category : #'*System-Object Storage' }
Metaclass >> objectForDataStream: refStrm [
	| dp |
	"I am about to be written on an object file.  Write a reference to a class in Smalltalk instead."

	dp := DiskProxy global: self theNonMetaClass name selector: #class
			args: (Array new).
	refStrm replace: self with: dp.
	^ dp

]

{ #category : #'*System-Object Storage' }
Metaclass >> storeDataOn: aDataStream [
	"I don't get stored.  Use a DiskProxy"

	self error: 'use a DiskProxy to store a Class'
]
