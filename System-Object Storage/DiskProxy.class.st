"
A DiskProxy is an externalized form of an object to write on a
DataStream. It contains a ""constructor"" message to regenerate
the object, in context, when sent a comeFullyUpOnReload message
(i.e. ""internalize"").

We are now using DiskProxy for shared system objects like StrikeFonts.

The idea is to define, for each kind of object that needs special
externalization, a class method that will internalize the object by
reconstructing it from its defining state. We call this a
""constructor"" method. Then externalize such an object as a frozen
message that invokes this method--a DiskProxy.

(Here is the old comment:
Constructing a new object is good for any object that (1) can not be
externalized simply by snapshotting and reloading its instance
variables (like a CompiledMethod or a Picture), or (2) wants to be
free to evolve its internal representation without making stored
instances obsolete (and dangerous). Snapshotting and reloading an
object""s instance variables is a dangerous breach of encapsulation.

The internal structure of the class is then free to evolve. All
externalized instances will be useful as long as the
constructor methods are maintained with the same semantics.

There may be several constructor methods for a particular class. This
is useful for (1) instances with characteristically different
defining state, and (2) newer, evolved forms of an object and its
constructors, with the old constructor methods kept around so old
data can still be properly loaded.)

Create one like this example from class Picture

    DiskProxy global: #Picture
            selector: #fromByteArray:
                args: (Array with: self storage asByteArray)

* See also subclass DiskProxyQ that will construct an object in
the above manner and then send it a sequence of messages. This may save
creating a wide variety of constructor methods. It is also useful because
the newly read-in DiskProxyQ can catch messages like #objectContainedIn:
(via #doesNotUnderstand:) and add them to the queue of messages to
send to the new object.

* We may also want a subclass of DiskProxy that evaluates a string
expression to compute the receiver of the constructor message.

My instance variables:
* globalObjectName -- the Symbol name of a global object in the
    System dictionary (usually a class).
* constructorSelector -- the constructor message selector Symbol to
    send to the global object (perform:withArguments:), typically a
    variation on newFrom:.
* constructorArgs -- the Array of arguments to pass in the
    constructor message.

-- 11/9/92 Jerry Morrison

"
Class {
	#name : #DiskProxy,
	#superclass : #Object,
	#instVars : [
		'globalObjectName',
		'preSelector',
		'constructorSelector',
		'constructorArgs'
	],
	#category : #'System-Object Storage'
}

{ #category : #'instance creation' }
DiskProxy class >> global: globalNameSymbol selector: selectorSymbol args: argArray [
    "Create a new DiskProxy constructor with the given
     globalNameSymbol, selectorSymbol, and argument Array.
     It will internalize itself by looking up the global object name
     in the SystemDictionary (Smalltalk) and sending it this message
     with these arguments."

    ^ self new global: globalNameSymbol
             selector: selectorSymbol
                 args: argArray
]

{ #category : #'i/o' }
DiskProxy >> comeFullyUpOnReload: smartRefStream [
	"Internalize myself into a fully alive object after raw loading from a DataStream. (See my class comment.)  DataStream will substitute the object from this eval for the DiskProxy."
	| globalObj symbol pr nn arrayIndex env |

	symbol := globalObjectName.
	"See if class is mapped to another name"
	(smartRefStream respondsTo: #renamed) ifTrue:
		[| maybeReadDataFromContext maybeReadArrayContext |
		"Ugh; so ugly and brittle.  If there were pragmas in the relevant methods we could search, etc. eem 7/3/2017 15:54"
		maybeReadArrayContext := thisContext sender sender sender sender.
		maybeReadDataFromContext := maybeReadArrayContext sender sender sender sender.
		"If in outPointers in an ImageSegment, remember original class name.  
		 See mapClass:installIn:.  Would be lost otherwise." "Anyone know where mapClass:installIn: is/was? eem 7/3/2017 15:55"
		(maybeReadDataFromContext method selector == #readDataFrom:size:
		 and: [maybeReadDataFromContext receiver class == NativeImageSegment
		 and: [maybeReadArrayContext method == (DataStream compiledMethodAt: #readArray)]]) ifTrue:
			[arrayIndex := maybeReadArrayContext tempAt: 4.
			"index var in readArray.  Later safer to find i on stack of context."
			smartRefStream renamedConv at: arrayIndex put: symbol].	"save original name"
		symbol := smartRefStream renamed at: symbol ifAbsent: [symbol]].	"map"
	env := Smalltalk globals.
	globalObj := env at: symbol ifAbsent: [
		preSelector == nil & (constructorSelector = #yourself) ifTrue: [
			Transcript cr; show: symbol, ' is undeclared.'.
			Undeclared declare: symbol from: env.
			^ nil].
		^ self error: 'Global "', symbol, '" not found'].
	((symbol == #World) and: [Smalltalk isMorphic not]) ifTrue: [
		self inform: 'These objects will work better if opened in a Morphic World.
Dismiss and reopen all menus.'].

	preSelector ifNotNil: [
		Symbol hasInterned: preSelector ifTrue: [:selector |
			[globalObj := globalObj perform: selector] on: Error do: [:ex |
				ex messageText = 'key not found' ifTrue: [^ nil].
				^ ex signal]]
	].

	constructorSelector ifNil: [^ globalObj].
	Symbol hasInterned: constructorSelector ifTrue: [:selector |
		[^ globalObj perform: selector withArguments: constructorArgs] on: Error do: [:ex |
			ex messageText = 'key not found' ifTrue: [^ nil].
			^ ex signal]
	].
				"args not checked against Renamed"
	^ nil 	"was not in proper form"
]

{ #category : #accessing }
DiskProxy >> constructorArgs [
	^ constructorArgs
]

{ #category : #accessing }
DiskProxy >> constructorSelector [
	^ constructorSelector
]

{ #category : #'initialize-release' }
DiskProxy >> global: globalNameSymbol preSelector: aSelector selector: selectorSymbol args: argArray [
	"Initialize self as a DiskProxy constructor with the given
	globalNameSymbol, selectorSymbol, and argument Array.
	I will internalize by looking up the global object name in the
	SystemDictionary (Smalltalk) and sending it this message with
	these arguments."

	globalObjectName := globalNameSymbol asSymbol.
	preSelector := aSelector asSymbol.
	constructorSelector := selectorSymbol asSymbol.
	constructorArgs := argArray.
]

{ #category : #'initialize-release' }
DiskProxy >> global: globalNameSymbol selector: selectorSymbol args: argArray [
	"Initialize self as a DiskProxy constructor with the given
	globalNameSymbol, selectorSymbol, and argument Array.
	I will internalize by looking up the global object name in the
	SystemDictionary (Smalltalk) and sending it this message with
	these arguments."

	(globalNameSymbol beginsWith: 'AnObsolete') ifTrue: [
		self error: 'Trying to write out, ', globalNameSymbol].
	globalObjectName := globalNameSymbol asSymbol.
	constructorSelector := selectorSymbol asSymbol.
	constructorArgs := argArray.
]

{ #category : #accessing }
DiskProxy >> globalObjectName [
	^ globalObjectName
]

{ #category : #accessing }
DiskProxy >> preSelector [

	^ preSelector
]

{ #category : #accessing }
DiskProxy >> preSelector: aSelector [

	preSelector := aSelector
]

{ #category : #printing }
DiskProxy >> printOn: aStream [
	"Try to report the name of the project"

	globalObjectName == #Project ifFalse: [^ super printOn: aStream].
	constructorArgs size > 0 ifFalse: [^ super printOn: aStream].
	constructorArgs first isString ifFalse: [^ super printOn: aStream].
	aStream nextPutAll: constructorArgs first, ' (on server)'
]

{ #category : #accessing }
DiskProxy >> simpleGlobalOrNil [
	"Return the object I refer to if it is a simple global in Smalltalk."

	preSelector ifNotNil: [^ nil].
	constructorSelector == #yourself ifFalse: [^ nil].
	^ Smalltalk at: globalObjectName ifAbsent: [nil].

]

{ #category : #'i/o' }
DiskProxy >> storeDataOn: aDataStream [
	"Besides just storing, get me inserted into references, so structures will know about class DiskProxy."

	super storeDataOn: aDataStream.
	aDataStream references at: self put: #none.
		"just so instVarInfo: will find it and put it into structures"
]
