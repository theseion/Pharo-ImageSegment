Extension { #name : #SystemDictionary }

{ #category : #'*System-Object Storage' }
SystemDictionary >> objectForDataStream: refStrm [
	| dp |
	"I am about to be written on an object file.  Write a reference to Smalltalk instead."

	dp := DiskProxy global: #Smalltalk selector: #yourself
			args: #().
	refStrm replace: self with: dp.
	^ dp
]

{ #category : #'*System-Object Storage' }
SystemDictionary >> storeDataOn: aDataStream [
	"I don't get stored.  Use a DiskProxy"

	self error: 'use a DiskProxy to store me'
]
