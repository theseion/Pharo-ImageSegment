"
ImageSegment is used to import old (interpreter VM era) projects into
new images. Instead of a VM primitive it uses LegacyImageSegmentLoader
to load objects from the segment. There are no methods for writing segments
 in the legacy format.

The original ImageSegment scheme used an ""endMarker"" object to enumerate
all objects in the segment, relying on the fact that all objects were layed out
continuously in object memory and could be traversed via #nextObject.
Since Spur makes no such guarantees the endMarker instance var has been
removed, instead the segment is converted into an Array of all objects,
so they can be enumerated.
"
Class {
	#name : #LegacyImageSegment,
	#superclass : #ImageSegment,
	#category : #'System-Object Storage'
}

{ #category : #'compact classes' }
LegacyImageSegment >> aComment [
	"Compact classes are a potential problem because a pointer to the class would not ordinarily show up in the outPointers.  We add the classes of all compact classes to outPointers, both for local and export segments.
	Compact classes are never allowed as roots.  No compact class may be in an Environment that is written out to disk.  (In local segments, the compact classes array should never have an ImageSegmentRootStub in it.  For export, fileIn the class first, then load a segment with instances of it.  The fileIn code can be pasted onto the front of the .extSeg file) 
	For local segments, a class may become compact while its instances are out on the disk.  Or it may become un-compact.  A compact class may change shape while some of its instances are on disk.  All three cases go through (ClassDescription updateInstancesFrom:).  If it can't rule out an instance being in the segment, it reads it in to fix the instances.  
	See Behavior.becomeCompact for the rules on Compact classes.  Indexes may not be reused.  This is so that an incoming export segment has its index available.  (Changes may be needed in the way indexes are assigned.)
	For export segments, a compact class may have a different shape.  The normal class reshape mechanism will catch this.  During the installation of the segment, objects will have the wrong version of their class momentarily.  We will change them back before we get caught.
	For export segments, the last two items in outPointers are the number 1717 and an array of the compact classes used in this segment.  (The classes in the array are converted from DiskProxies by SmartRefStream.)  If that class is not compact in the new image, the instances are recopied.
	"
]

{ #category : #'instance change shape' }
LegacyImageSegment >> ifOutPointer: anObject thenAllObjectsDo: aBlock [
	"Compatibility with NativeImageSegment (see e.g. MorphicProject class>>releaseProjectReferences:).
	 Do nothing since LegacyImageSegments are load-only. (Not sure if this is right, eem 7/3/2017 15:19)"
]

{ #category : #'read/write segment primitives' }
LegacyImageSegment >> loadSegmentFrom: segment outPointers: outPointers [
	"Attempt to load the segment into memory (reify the objects in segment
	 as real objects), using outPointers to bind references to objects not in the
	 segment.  Answer a collection of all the objects in the segment."
	^ImageSegmentLoader new loadSegmentFrom: segment outPointers: outPointers
]
