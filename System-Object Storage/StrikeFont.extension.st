Extension { #name : #StrikeFont }

{ #category : #'*System-Object Storage' }
StrikeFont >> objectForDataStream: refStrm [ 
	"I am about to be written on an object file.  Write a reference to a known Font in the other system instead.  "
	"A path to me"
	| dp |
	(TextSharedInformation 
		at: #forceFontWriting
		ifAbsent: [ false ]) ifTrue: [ ^ self ].
	"special case for saving the default fonts on the disk.  See collectionFromFileNamed:"
	dp := DiskProxy 
		global: #StrikeFont
		selector: #familyName:size:emphasized:
		args: (Array 
				with: self familyName
				with: self height
				with: self emphasis).
	refStrm 
		replace: self
		with: dp.
	^ dp
]
