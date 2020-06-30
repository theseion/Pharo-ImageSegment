"
An ImageSegmentRootStub is a stub that replaces one of the root of an ImageSegment that has been extracted from the Squeak ObjectMemory.  It has two very simple roles:

1.  If any message is sent to one of these objects, it will be caught by doesNotUnderstand:, and bring about a reinstallation of the missing segment.  This exception is caused by the fact that no other messages are defined in this class, and neither does it inherit any from above, since its superclass is nil.  When the reinstallation has been accomplished, the message will be resent as though nothing was amiss.

2.  If one of these objects is a class, and a message is sent to one of its instances, it will cause a similar fault which will be caught by cannotInterpret:.  This exception is caused by a somewhat more subtle condition:  the primitive operations of the virtual machine do not have time to check whether classes are resident or not -- they assume that all classes are resident.  However every non-cached message lookup does test for a nil in the methodDictionary slot.  If a rootStub replaces a class (or any behavior), it masquerades as the class, but it will have a nil in the slot where the method Dictionary is expected.  This will cause the VM to send cannotInterpret:, eventually leading to the same process for reinstalling the missing segment and resending the message as above.

Just to be on the safe side, a rootStub that replaces a Behavior also carries a copy of both the superclass and format fields from the original class.  This insures that, even if some operations of the VM require these values, things will continue to operate properly when the segment is absent.
"
Class {
	#name : #ImageSegmentRootStub,
	#superclass : #ProtoObject,
	#instVars : [
		'shadowSuper',
		'shadowMethodDict',
		'shadowFormat',
		'imageSegment'
	],
	#classVars : [
		'FaultLogs',
		'LoggingFaults'
	],
	#category : #'System-Object Storage'
}

{ #category : #settings }
ImageSegmentRootStub class >> doLogFaults [  "ImageSegmentRootStub doLogFaults"

	FaultLogs := Dictionary new.
	LoggingFaults := true.
]

{ #category : #settings }
ImageSegmentRootStub class >> dontLogFaults [  "ImageSegmentRootStub dontLogFaults"

	FaultLogs := Dictionary new.
	LoggingFaults := false.
]

{ #category : #accessing }
ImageSegmentRootStub class >> faultLogs [  "ImageSegmentRootStub faultLogs"  "<-- inspect it"

	^ FaultLogs
]

{ #category : #settings }
ImageSegmentRootStub class >> startLoggingFaults [  "ImageSegmentRootStub startLoggingFaults"

	FaultLogs := Dictionary new.
	LoggingFaults := true.
]

{ #category : #settings }
ImageSegmentRootStub class >> stopLoggingFaults [  "ImageSegmentRootStub stopLoggingFaults"

	FaultLogs := Dictionary new.
	LoggingFaults := false.
]

{ #category : #'fetch from disk' }
ImageSegmentRootStub >> doesNotUnderstand: aMessage [ 
	 | segmentName |
"Any normal message sent to this object is really intended for another object that is in a non-resident imageSegment.  Reinstall the segment and resend the message."

	segmentName := imageSegment segmentName.
	imageSegment install.
	LoggingFaults ifTrue:		"Save the stack printout to show who caused the fault"
		[FaultLogs at: Time millisecondClockValue printString
			put: (String streamContents:
				[:strm | 
				strm nextPutAll: segmentName; cr.
				strm print: self class; space; print: aMessage selector; cr.
				(thisContext sender stackOfSize: 30)
					do: [:item | strm print: item; cr]])].

	"NOTE:  The following should really be (aMessage sentTo: self)
		in order to recover properly from a fault in a super-send,
		however, the lookupClass might be bogus in this case, and it's
		almost unthinkable that the first fault would be a super send."
	^ self perform: aMessage selector withArguments: aMessage arguments
]

{ #category : #basics }
ImageSegmentRootStub >> isInMemory [
	"We are a place holder for an object that is out."
	^ false
]

{ #category : #'fetch from disk' }
ImageSegmentRootStub >> xxSuperclass: superclass format: format segment: segment [

	"Set up fields like a class but with null methodDict"
	shadowSuper := superclass.
	shadowMethodDict := nil.
	shadowFormat := format.
	imageSegment := segment.

]

{ #category : #'fetch from disk' }
ImageSegmentRootStub >> xxxClass [
	"Primitive. Answer the object which is the receiver's class. Essential. See 
	Object documentation whatIsAPrimitive."

	<primitive: 111>
	self primitiveFailed
]

{ #category : #'fetch from disk' }
ImageSegmentRootStub >> xxxSegment [
	^ imageSegment
]
