Extension { #name : #MethodChangeRecord }

{ #category : #'*System-Object Storage' }
MethodChangeRecord >> storeDataOn: aDataStream [
	| oldMethod |
	oldMethod := currentMethod.
	currentMethod := nil.
	super storeDataOn: aDataStream.
	currentMethod := oldMethod.

]
