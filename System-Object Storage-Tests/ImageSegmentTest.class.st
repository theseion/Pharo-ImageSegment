Class {
	#name : #ImageSegmentTest,
	#superclass : #TestCase,
	#instVars : [
		'fileReference'
	],
	#category : #'System-Object Storage-Tests'
}

{ #category : #accessing }
ImageSegmentTest >> fileReference [
	^ fileReference ifNil: [
		fileReference := FileLocator imageDirectory asFileReference / ('segment', UUID new asString, '.bin') ]
]

{ #category : #running }
ImageSegmentTest >> setUp [
	super setUp.
	
	self fileReference ensureDelete
]

{ #category : #tests }
ImageSegmentTest >> testWriteAndReadSimpleSegment [
	| point segment reloaded |
	point := 1@2.
	segment := NativeImageSegment new.
	segment copyFromRootsForExport: (Array with: point).
	
	self deny: self fileReference exists.
	MultiByteFileStream
		forceNewFileNamed: self fileReference pathString
		do: [ :stream |
			(SmartRefStream on: stream) nextPutObjOnly: segment ].
	self assert: self fileReference exists.
	
	reloaded := (MultiByteFileStream
		readOnlyFileNamed: self fileReference pathString
		do: [ :stream | stream fileInObjectAndCode ]) arrayOfRoots first.
	self deny: point identicalTo: reloaded.
	self assert: point equals: reloaded
	
]
