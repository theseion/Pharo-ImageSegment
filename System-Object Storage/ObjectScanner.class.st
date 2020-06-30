"
An instance of this class is the compiler's context for filing in a SmartRefStream containing instance-specific classes.  When the old name of a new object's class conflicts with an existing class name, install a class var in me.  It has the old name but points at the new class.  The compiler uses it when compiling the code in the fileIn.  Fill the SmartRefStream's renamed class dictionary.

An object fileout:
!ObjectScanner new initialize!      ""allow me to take control with scanFrom:""

Player subclass: Player23 instanceVariableNames: 'foo' classVariableNames: '' 
	poolDictionaries: nil category: 'Instance Specific'!
	""I prescan this and (self rename: #Player23 toBe: #Player30)""

!Player23 methodsFor: 'all' stamp: 'tk 3/9/98 18:58'!	""actually sent to Player30""
foo
	^ foo! !

!self smartRefStream!<binary representation of the objects>!



"
Class {
	#name : #ObjectScanner,
	#superclass : #Object,
	#instVars : [
		'pvt3SmartRefStrm'
	],
	#category : #'System-Object Storage'
}

{ #category : #'initialize-release' }
ObjectScanner >> clear [
	"remove all old class vars.  They were UniClasses being remapped to aviod a name conflict."

	self class classPool keys do: [:key |
		self class classPool removeKey: key].	"brute force"
]

{ #category : #'initialize-release' }
ObjectScanner >> initialize [
	"remove all old class vars that are not instance-specific classes being renamed"

	self clear.
	"Most importantly, return self, so a fileIn will let ObjectScanner seize control.  So UniClasses can be remapped.  See the transfer of control where ReadWriteStream fileIn calls scanFrom:"
]

{ #category : #scanning }
ObjectScanner >> lookAhead: aChunk [
	"See if this chunk is a class Definition, and if the new class name already exists and is instance-specific.  Modify the chunk, and record the rename in the SmartRefStream and in me."

	| pieces sup oldName existing newName newDefn |
	aChunk size < 90 ifTrue: [^ aChunk].		"class defn is big!"
	(aChunk at: 1) == $! ifTrue: [^ aChunk].	"method def, fast exit"
	pieces := (aChunk copyFrom: 1 to: (300 min: aChunk size)) findTokens: ' #	\' withCRs.
	pieces size < 3 ifTrue: [^ aChunk].	"really bigger, but just took front"
	(pieces at: 2) = 'subclass:' ifFalse: [^ aChunk].
	sup := Smalltalk at: (pieces at: 1) asSymbol ifAbsent: [^ aChunk].
	sup class class == Metaclass ifFalse: [^ aChunk].
	((oldName := pieces at: 3) at: 1) canBeGlobalVarInitial ifFalse: [^ aChunk].
	oldName := oldName asSymbol.
	(Smalltalk includesKey: oldName) ifFalse: [^ aChunk].	"no conflict"
	existing := Smalltalk at: oldName.
	(existing isKindOf: Class) ifFalse: [^ aChunk].	"Write over non-class global"
	"Is a UniClass"
	Error signal: 'Can''t happen!'
]

{ #category : #utilities }
ObjectScanner >> rename: existingName toBe: newName [
	"See if there is a conflict between what the fileIn wants to call the new UniClass (Player23) and what already exists for another unique instance.  If conflict, make a class variable to intercept the existingName and direct it to class newName."

	self flag: #environments.
	existingName = newName ifFalse: [
		self class ensureClassPool.	"create the dictionary"
		"can't use addClassVarName: because it checks for conflicts with Smalltalk"
		(self class classPool includesKey: existingName) ifFalse: 
			["Pick up any refs in Undeclared"
			self class classPool declare: existingName from: Undeclared].
		self class classPool at: existingName put: (Smalltalk at: newName).
		pvt3SmartRefStrm renamed at: existingName put: newName]
]

{ #category : #scanning }
ObjectScanner >> scanFrom: aByteStream [
	"Sieze control of the fileIn.  Put myself in as the context.  If any UniClasses (for just one instance) are defined, they will do it through me, and I will look for conflicting class names.  If so, install the old name as a class var of me, so the compile will work.  Tell my SmartRefStream about renaming the class."

	| valWithOddName47 scannerNamed53 chunkNamed117 |
	pvt3SmartRefStrm := SmartRefStream on: aByteStream.
	aByteStream ascii.
	[ aByteStream atEnd ]
		whileFalse: [ aByteStream skipSeparators.
			valWithOddName47 := (aByteStream peekFor: $!)
				ifTrue: [ chunkNamed117 := aByteStream nextChunk.	"debug"
					scannerNamed53 := self class compiler
						source: chunkNamed117;
						logged: false;
						receiver: self;
						evaluate.
					scannerNamed53 class == self class
						ifTrue: [ "I already am the scanner for this file" ]
						ifFalse: [ scannerNamed53 scanFrom: aByteStream ] ]
				ifFalse: [ chunkNamed117 := aByteStream nextChunk.
					chunkNamed117 := self lookAhead: chunkNamed117.
					self class compiler
						source: chunkNamed117;
						logged: true;
						receiver: self;
						evaluate ].
			aByteStream skipStyleChunk ].
	^ valWithOddName47
]

{ #category : #scanning }
ObjectScanner >> scanFrom: aByteStream environment: anEnvironment [
	"This should probably be reimplemented using an environment
	for compilation. For now, don't change anything"
	^ self scanFrom: aByteStream
]

{ #category : #accessing }
ObjectScanner >> smartRefStream [

	^ pvt3SmartRefStrm
]
