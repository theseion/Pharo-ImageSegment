Extension { #name : #Object }

{ #category : #'*System-Object Storage' }
Object >> convertToCurrentVersion: varDict refStream: smartRefStrm [
	"subclasses should implement if they wish to convert old instances to modern ones"
	"this method should not be removed since SmartRefStream use it"
]

{ #category : #'*System-Object Storage' }
Object class >> createFrom: aSmartRefStream size: varsOnDisk version: instVarList [
	"Create an instance of me so objects on the disk can be read in.  Tricky part is computing the size if variable.  Inst vars will be filled in later.  "

	^ self isVariable
		ifFalse: [self basicNew]
		ifTrue: ["instVarList is names of old class's inst vars plus a version number" 
				self basicNew: (varsOnDisk - (instVarList size - 1))]

]

{ #category : #'*System-Object Storage' }
Object >> indexIfCompact [

	^0		"helps avoid a #respondsTo: in publishing"
]

{ #category : #'*System-Object Storage' }
Object >> objectForDataStream: refStrm [
    "Return an object to store on an external data stream."

    ^ self
]

{ #category : #'*System-Object Storage' }
Object >> rootStubInImageSegment: imageSegment [

	^ ImageSegmentRootStub new
		xxSuperclass: nil
		format: nil
		segment: imageSegment
]

{ #category : #'*System-Object Storage' }
Object >> storeDataOn: aDataStream [
	"Store myself on a DataStream.  Answer self.  This is a low-level DataStream/ReferenceStream method. See also objectToStoreOnDataStream.  NOTE: This method must send 'aDataStream beginInstance:size:' and then (nextPut:/nextPutWeak:) its subobjects.  readDataFrom:size: reads back what we write here."
	| cntInstVars cntIndexedVars |

	cntInstVars := self class instSize.
	cntIndexedVars := self basicSize.
	aDataStream
		beginInstance: self class
		size: cntInstVars + cntIndexedVars.
	1 to: cntInstVars do:
		[:i | aDataStream nextPut: (self instVarAt: i)].

	"Write fields of a variable length object.  When writing to a dummy 
		stream, don't bother to write the bytes"
	((aDataStream byteStream class == DummyStream) and: [self class isBits]) ifFalse: [
		1 to: cntIndexedVars do:
			[:i | aDataStream nextPut: (self basicAt: i)]].

]
