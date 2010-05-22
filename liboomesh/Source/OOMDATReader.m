/*
	OOMDATReader.m
	liboomesh
	
	
	Copyright © 2010 Jens Ayton.
	
	Permission is hereby granted, free of charge, to any person obtaining a
	copy of this software and associated documentation files (the “Software”),
	to deal in the Software without restriction, including without limitation
	the rights to use, copy, modify, merge, publish, distribute, sublicense,
	and/or sell copies of the Software, and to permit persons to whom the
	Software is furnished to do so, subject to the following conditions:
	
	The above copyright notice and this permission notice shall be included in
	all copies or substantial portions of the Software.
	
	THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
	THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
	FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
	DEALINGS IN THE SOFTWARE.
*/

#import "OOMDATReader.h"
#import "OOMProblemReportManager.h"
#import "OOMDATLexer.h"
#import "CollectionUtils.h"
#import "OOCollectionExtractors.h"

#import "OOMVertex.h"
#import "OOMFace.h"
#import "OOMFaceGroup.h"
#import "OOMMesh.h"


static void CleanVector(Vector *v)
{
	/*	Avoid duplicate vertices that differ only in sign of 0. This happens
		quite easily in practice.
	 */
	if (v->x == -0.0f)  v->x = 0.0f;
	if (v->y == -0.0f)  v->y = 0.0f;
	if (v->z == -0.0f)  v->z = 0.0f;
}


/*	Triangle from source file representation, with associated metadata.
*/
typedef struct RawDATTriangle
{
	OOUInteger			vertex[3];
	Vector				position[3];	// Cache of vertex position, the attribute we use most often.
	Vector				normal;
	Vector				tangent;
	Vector2D			texCoords[3];	// Texture coordinates are stored separately because a given file vertex may be used for multiple "real" vertices with different texture coordinates.
	float				area;			// Actually twice area.
	
	uint16_t			smoothGroup;
	uint8_t				materialIndex;
} RawDATTriangle;


/*	VertexFaceRef
	List of indices of faces used by a given vertex.
	Always access using the provided functions.
*/
enum
{
	kVertexFaceDefInternalCount	= 7
};

typedef struct VertexFaceRef
{
	uint16_t			internCount;
	uint16_t			internFaces[kVertexFaceDefInternalCount];
	NSMutableArray		*extra;
} VertexFaceRef;


static void VFRAddFace(VertexFaceRef *vfr, OOUInteger index);
static OOUInteger VFRGetCount(VertexFaceRef *vfr);
static OOUInteger VFRGetFaceAtIndex(VertexFaceRef *vfr, OOUInteger index);
static void VFRRelease(VertexFaceRef *vfr);	// N.b. does not zero out the struct.


enum
{
	kMaxDATMaterials			= 8
};


@interface OOMDATReader (Private)

- (void) priv_reportParseError:(NSString *)format, ...;
- (void) priv_reportBasicParseError:(NSString *)expected;
- (void) priv_reportMallocFailure;

- (BOOL) priv_checkNormalsAndAdjustWinding;
- (BOOL) priv_generateFaceTangents;
- (BOOL) priv_calculateVertexNormalsAndTangents;
- (BOOL) priv_calculateVertexTangents;
- (BOOL) priv_buildGroups;

- (BOOL) priv_parseVERTEX;
- (BOOL) priv_parseFACES;
- (BOOL) priv_parseTEXTURES;
- (BOOL) priv_parseNAMES;
- (BOOL) priv_parseNORMALS;
- (BOOL) priv_parseTANGENTS;

/*	Dump a copy of the file. If smoothing is used, explict normals and
	tangents are used. Currently, this does not take smooth groups into account.
*/
- (void) priv_dumpDAT;

@end


@implementation OOMDATReader

- (id) initWithPath:(NSString *)path issues:(id <OOMProblemReportManager>)ioIssues
{
	if ((self = [super init]))
	{
		_issues = [ioIssues retain];
		_path = [path copy];
		_brokenSmoothing = YES;
		
		_lexer = [[OOMDATLexer alloc] initWithPath:_path issues:_issues];
		if (_lexer == nil)  DESTROY(self);
	}
	
	return self;
}


- (void) dealloc
{
	DESTROY(_issues);
	DESTROY(_path);
	DESTROY(_lexer);
	
	[super dealloc];
}


OOUInteger gHashCollisions;


- (void) parse
{
	if (_lexer == nil)  return;	// Parsed already or initialization failed.
	
	NSAutoreleasePool			*pool = nil;
	BOOL						OK = YES;
	NSString					*secName = nil;
	
	pool = [NSAutoreleasePool new];
	
	// Get vertex count.
	if (OK)
	{
		OK = [_lexer expectLiteral:"NVERTS"] && [_lexer readInteger:&_fileVertexCount];
		if (!OK)  [self priv_reportBasicParseError:@"\"NVERTS\" and vertex count"];
	}
	
	// Get face count.
	if (OK)
	{
		OK = [_lexer expectLiteral:"NFACES"] && [_lexer readInteger:&_fileFaceCount];
		if (!OK)  [self priv_reportBasicParseError:@"\"NFACES\" and face count"];
	}
	
	// Load VERTEX section.
	if (OK)
	{
		OK = [_lexer expectLiteral:"VERTEX"];
		if (OK)  OK = [self priv_parseVERTEX];
		else  [self priv_reportBasicParseError:@"\"VERTEX\""];
	}
	
	// Load FACES section.
	if (OK)
	{
		OK = [_lexer expectLiteral:"FACES"];
		if (OK)  [self priv_parseFACES];
		else  [self priv_reportBasicParseError:@"\"FACES\""];
	}
	
	/*	NOTE: we don't check for errors when reading secName, because this
		would lead to failure for files that don't have an END token, which
		we'd rather just warn about.
	*/
	if (OK)  secName = [_lexer nextToken];
	
	// Load TEXTURES section if present.
	if (OK && [secName isEqualToString:@"TEXTURES"])
	{
		OK = [self priv_parseTEXTURES];
		if (OK)  secName = [_lexer nextToken];
		
		// NAMES is only valid after TEXTURES.
		if (OK && [secName isEqualToString:@"NAMES"])
		{
			OK = [self priv_parseNAMES];
			if (OK)  secName = [_lexer nextToken];
		}
	}
	else
	{
		_materialCount = 1;
	}

	
	// Load NORMALS section if present.
	if (OK && [secName isEqualToString:@"NORMALS"])
	{
		OK = [self priv_parseNORMALS];
		if (OK)  secName = [_lexer nextToken];
		
		// TANGENTS is only valid after NORMALS.
		if (OK && [secName isEqualToString:@"TANGENTS"])
		{
			OK = [self priv_parseTANGENTS];
			if (OK)  secName = [_lexer nextToken];
		}
	}
	
	//	Check for END.
	if (OK)
	{
		if (![secName isEqualToString:@"END"])
		{
			if (secName == nil)
			{
				OOMReportWarning(_issues, @"missingEnd", @"The document is missing an END line. This may indicate that the file is damaged.");
			}
			else
			{
				OOMReportWarning(_issues, @"missingEnd", @"The document continues beyond where it was expected to end (expected \"END\", found \"%@\"). It may be of a newer format, and important information may be missed.", secName);
			}
		}
	}
	
	if (!_smoothing || _explicitNormals)  _usesSmoothGroups = NO;
	
	
	//	Post-processing.
	if (OK && !_explicitNormals)
	{
		OK = [self priv_checkNormalsAndAdjustWinding];
	}
	if (OK && !_explicitTangents)
	{
		OK = [self priv_generateFaceTangents];
	}
	if (OK && !_explicitNormals && _smoothing)
	{
		//	Vertex smoothing.
		OK = [self priv_calculateVertexNormalsAndTangents];
	}
	else
	{
		//	Only YES after parsing if actually used, see header.
		_brokenSmoothing = NO;
		if (OK && _explicitNormals && !_explicitTangents)
		{
			OK = [self priv_calculateVertexTangents];
		}
	}
	
//	if (OK)  [self priv_dumpDAT];
	
	
	//	Convert to sane format.
	if (OK)
	{
		OK = [self priv_buildGroups];
	}
	printf("Hash collisions: %lu\n", (unsigned long)gHashCollisions);
	
	for (OOUInteger vIter = 0; vIter < _fileVertexCount; vIter++)
	{
		VFRRelease(&_faceRefs[vIter]);
	}
	_faceRefs = NULL;
	
	DESTROY(_lexer);
	DESTROY(_materialKeys);
	free(_fileVertices);
	_fileVertices = NULL;
	free(_rawTriangles);
	_rawTriangles = NULL;
	
	[pool drain];
}


- (OOMMesh *) mesh
{
	[self parse];
	return _mesh;
}


- (BOOL) smoothing
{
	return _smoothing;
}


- (void) setSmoothing:(BOOL)value
{
	if (_lexer != nil)
	{
		_smoothing = !!value;
	}
}


- (BOOL) brokenSmoothing
{
	return _brokenSmoothing;
}


- (void) setBrokenSmoothing:(BOOL)value
{
	if (_lexer != nil)
	{
		_brokenSmoothing = !!value;
	}
}


- (OOUInteger) fileVertexCount
{
	[self parse];
	return _fileVertexCount;
}


- (OOUInteger) fileFaceCount
{
	[self parse];
	return _fileFaceCount;
}

@end


@implementation OOMDATReader (Private)

- (void) priv_reportParseError:(NSString *)format, ...
{
	NSString *base = OOMLocalizeProblemString(_issues, @"Parse error on line %u of %@: %@.");
	format = OOMLocalizeProblemString(_issues, format);
	
	va_list args;
	va_start(args, format);
	NSString *message = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
	va_end(args);
	
	message = [NSString stringWithFormat:base, [_lexer lineNumber], [[NSFileManager defaultManager] displayNameAtPath:_path], message];
	[_issues addProblemOfType:kOOMProblemTypeError key:@"parseError" message:message];
}


- (void) priv_reportBasicParseError:(NSString *)expected
{
	[self priv_reportParseError:@"expected %@, got %@", expected, [_lexer currentTokenString]];
}


- (void) priv_reportMallocFailure
{
	OOMReportError(_issues, @"allocFailed", @"Not enough memory to read %@.", [[NSFileManager defaultManager] displayNameAtPath:_path]);
}


- (BOOL) priv_parseVERTEX
{
	BOOL OK = YES;
	
	_fileVertices = malloc(sizeof *_fileVertices * _fileVertexCount);
	_faceRefs = calloc(sizeof *_faceRefs, _fileVertexCount);
	if (_fileVertices == NULL || _faceRefs == NULL)
	{
		[self priv_reportMallocFailure];
		return NO;
	}
	
	for (OOUInteger vIter = 0; vIter < _fileVertexCount; vIter++)
	{
		// VERTEX entry format: <float v.x> <float v.y> <float v.z>
		
		Vector v;
		OK = [_lexer readReal:&v.x] &&
		[_lexer readReal:&v.y] &&
		[_lexer readReal:&v.z];
		if (!OK)
		{
			[self priv_reportBasicParseError:@"number"];
			return NO;
		}
		CleanVector(&v);
		
		_fileVertices[vIter] = [OOMVertex vertexWithPosition:v];
	}
	
	return YES;
}


- (BOOL) priv_parseFACES
{
	BOOL OK = YES;
	
	_rawTriangles = malloc(sizeof *_rawTriangles * _fileFaceCount);
	if (_rawTriangles == NULL)
	{
		[self priv_reportMallocFailure];
		return NO;
	}
	
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	NSMutableDictionary *smoothGroups = [NSMutableDictionary dictionary];
	
	for (OOUInteger fIter = 0; fIter != _fileFaceCount; fIter++)
	{
		// FACES entry format: <int smoothGroupID> <int unused1> <int unused2> <float n.x> <float n.y> <float n.z> <int vertexCount = 3> <int v0> <int v1> <int v2>
		
		RawDATTriangle *triangle = &_rawTriangles[fIter];
		OOUInteger smoothGroupID, unused, faceVertexCount;
		OK = [_lexer readInteger:&smoothGroupID] &&
		[_lexer readInteger:&unused] &&
		[_lexer readInteger:&unused];
		if (!OK)
		{
			[self priv_reportBasicParseError:@"integer"];
			return NO;
		}
		
		/*	Canonicalize smooth group IDs. Starts with number 1, using 0
		 as "unknown" marker.
		 */
		NSNumber *key = [NSNumber numberWithUnsignedInteger:smoothGroupID];
		uint16_t smoothGroup = [smoothGroups oo_unsignedIntForKey:key];
		if (smoothGroup == 0)
		{
			smoothGroup = [smoothGroups count] + 1;
			[smoothGroups setObject:[NSNumber numberWithUnsignedInteger:smoothGroup] forKey:key];
		}
		
		triangle->smoothGroup = smoothGroup;
		
		OK = [_lexer readReal:&triangle->normal.x] &&
		[_lexer readReal:&triangle->normal.y] &&
		[_lexer readReal:&triangle->normal.z];
		if (!OK)
		{
			[self priv_reportBasicParseError:@"number"];
			return NO;
		}
		CleanVector(&triangle->normal);
		
		/*	Oolite (and Dry Dock) attempt to "support" more than three
		 vertices for legacy files by only using the first three and
		 then skipping the rest. However, this leaves the texture
		 coordinates in the TEXTURES section ill-defined. Without a
		 real example of such a file, it's not clear how to implement
		 this support in a way that would actually be useful.
		 */
		OK = [_lexer readInteger:&faceVertexCount];
		if (!OK || faceVertexCount != 3)
		{
			[self priv_reportBasicParseError:@"3"];
			return NO;
		}
		
		OK = [_lexer readInteger:&triangle->vertex[0]] &&
		[_lexer readInteger:&triangle->vertex[1]] &&
		[_lexer readInteger:&triangle->vertex[2]];
		if (!OK)
		{
			[self priv_reportBasicParseError:@"integer"];
			return NO;
		}
		
		for (OOUInteger vIter = 0; vIter < 3; vIter++)
		{
			//	Track vertex->face relationships.
			VFRAddFace(&_faceRefs[triangle->vertex[vIter]], fIter);
			
			//	Cache vertex positions for post-processing.
			triangle->position[vIter] = [_fileVertices[triangle->vertex[vIter]] position];
		}
	}
	
	_usesSmoothGroups = [smoothGroups count] > 1;
	[pool drain];
	
	return YES;
}


- (BOOL) priv_parseTEXTURES
{
	BOOL OK = YES;
	
	_materialKeys = [NSMutableArray new];
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	NSMutableDictionary *materialKeyToIndex = [NSMutableDictionary dictionaryWithCapacity:kMaxDATMaterials];
	
	for (OOUInteger fIter = 0; fIter < _fileFaceCount; fIter++)
	{
		// TEXTURES entry format: <string materialName> <float scaleS> <float scaleT> (<float s> <float t>)*3
		
		RawDATTriangle *triangle = &_rawTriangles[fIter];
		NSString *materialKey = nil;
		OK = [_lexer readString:&materialKey];
		if (!OK)
		{
			[self priv_reportBasicParseError:@"string"];
			return NO;
		}
		
		NSNumber *materialIndex = [materialKeyToIndex objectForKey:materialKey];
		if (materialIndex == 0)
		{
			materialIndex = [NSNumber numberWithUnsignedInteger:_materialCount++];
			[materialKeyToIndex setObject:materialIndex forKey:materialKey];
			[_materialKeys addObject:materialKey];
		}
		triangle->materialIndex = [materialIndex unsignedIntValue];
		
		float scaleS, scaleT;
		OK = [_lexer readReal:&scaleS] && [_lexer readReal:&scaleT];
		
		for (OOUInteger vIter = 0; vIter < 3; vIter++)
		{
			float s, t;
			OK = OK && [_lexer readReal:&s] && [_lexer readReal:&t];
			triangle->texCoords[vIter].x = s / scaleS;
			triangle->texCoords[vIter].y = t / scaleT;
		}
		
		if (!OK)
		{
			[self priv_reportBasicParseError:@"number"];
			return NO;
		}
	}
	[pool drain];
	
	return YES;
}


- (BOOL) priv_parseNAMES
{
	OOUInteger nameCount;
	if (![_lexer readInteger:&nameCount])
	{
		[self priv_reportBasicParseError:@"integer after NAMES"];
		return NO;
	}
	
	for (OOUInteger nIter = 0; nIter < nameCount; nIter++)
	{
		// NAMES entry format: <newline-terminated-string>
		
		NSString *realName = nil;
		if (![_lexer readUntilNewline:&realName])
		{
			[self priv_reportBasicParseError:@"string"];
			return NO;
		}
		
		[_materialKeys replaceObjectAtIndex:nIter withObject:realName];
	}
	
	return YES;
}


- (BOOL) priv_parseNORMALS
{
	_explicitNormals = YES;
	BOOL OK = YES;
	
	for (OOUInteger vIter = 0; vIter < _fileVertexCount; vIter++)
	{
		// NORMALS entry format: <float n.x> <float n.y> <float n.z>
		
		Vector normal;
		OK = [_lexer readReal:&normal.x] &&
			 [_lexer readReal:&normal.y] &&
			 [_lexer readReal:&normal.z];
		if (!OK)
		{
			[self priv_reportBasicParseError:@"number"];
			return NO;
		}
		
		CleanVector(&normal);
		_fileVertices[vIter] = [_fileVertices[vIter] vertexByAddingAttribute:OOMArrayFromVector(normal)
																	  forKey:kOOMNormalAttributeKey];
	}
	
	return YES;
}


- (BOOL) priv_parseTANGENTS
{
	_explicitTangents = YES;
	BOOL OK = YES;
	
	for (OOUInteger vIter = 0; vIter < _fileVertexCount; vIter++)
	{
		// TANGENTS entry format: <float t.x> <float t.y> <float t.z>
		
		Vector tangent;
		OK = [_lexer readReal:&tangent.x] &&
			 [_lexer readReal:&tangent.y] &&
			 [_lexer readReal:&tangent.z];
		if (!OK)
		{
			[self priv_reportBasicParseError:@"number"];
			return NO;
		}
		
		CleanVector(&tangent);
		_fileVertices[vIter] = [_fileVertices[vIter] vertexByAddingAttribute:OOMArrayFromVector(tangent)
																	  forKey:kOOMTangentAttributeKey];
	}
	
	return YES;
}


//	NOTE: these methods exactly duplicates Oolite 1.x behaviour, including bugs and slowness.

- (BOOL) priv_checkNormalsAndAdjustWinding
{
	for (OOUInteger fIter = 0; fIter < _fileFaceCount; fIter++)
	{
		RawDATTriangle *triangle = &_rawTriangles[fIter];
		Vector v0 = triangle->position[0];
		Vector v1 = triangle->position[1];
		Vector v2 = triangle->position[2];
		Vector normal = triangle->normal;
		
		Vector calculatedNormal = normal_to_surface(v2, v1, v0);
		if (vector_equal(normal, kZeroVector))
		{
			/*	If the existing normal is 0, we want to choose between the
				better of calculatedNormal and -calculatedNormal.
			*/
			normal = vector_flip(calculatedNormal);
			triangle->normal = normal;
		}
		
		/*	This calculation is broken. It should be:
				if (dot_product(normal, calculatedNormal) < 0.0f)
			But see above regarding bugwards-compatibility.
		*/
		if (normal.x * calculatedNormal.x < 0 || normal.y * calculatedNormal.y < 0 || normal.z * calculatedNormal.z < 0)
		{
			//	normal lies in the WRONG direction!
			//	reverse the winding.
			OOUInteger vi0 = triangle->vertex[0];
			triangle->vertex[0] = triangle->vertex[2];
			triangle->vertex[2] = vi0;
			
			//	Don't forget texture coordinates.
			Vector2D t0 = triangle->texCoords[0];
			triangle->texCoords[0] = triangle->texCoords[2];
			triangle->texCoords[2] = t0;
		}
	}
	
	return YES;
}


- (BOOL) priv_generateFaceTangents
{
	for (OOUInteger fIter = 0; fIter < _fileFaceCount; fIter++)
	{
		RawDATTriangle *triangle = &_rawTriangles[fIter];
		
		/*	Generate tangents, i.e. vectors that run in the direction of the s
			texture coordinate. Based on code I found in a forum somewhere and
			then lost track of. Sorry to whomever I should be crediting.
			-- Ahruman 2008-11-23
		*/
		Vector v0 = triangle->position[0];
		Vector v1 = triangle->position[1];
		Vector v2 = triangle->position[2];
		
		Vector vAB = vector_subtract(v1, v0);
		Vector vAC = vector_subtract(v2, v0);
		Vector nA = triangle->normal;
		
		//	projAB = vAB - (nA · vAB) * nA
		Vector vProjAB = vector_subtract(vAB, vector_multiply_scalar(nA, dot_product(nA, vAB)));
		Vector vProjAC = vector_subtract(vAC, vector_multiply_scalar(nA, dot_product(nA, vAC)));
		
		//	delta s/t
		float dsAB = triangle->texCoords[1].x - triangle->texCoords[0].x;
		float dsAC = triangle->texCoords[2].x - triangle->texCoords[0].x;
		float dtAB = triangle->texCoords[1].y - triangle->texCoords[0].y;
		float dtAC = triangle->texCoords[2].y - triangle->texCoords[0].y;
		
		if (dsAC * dtAB > dsAB * dtAC)
		{
			dsAB = -dsAB;
			dsAC = -dsAC;
		}
		
		Vector tangent = vector_subtract(vector_multiply_scalar(vProjAB, dsAC), vector_multiply_scalar(vProjAC, dsAB));
		//	Rotate 90 degrees. Done this way because I'm too lazy to grok the code above.
		triangle->tangent = cross_product(nA, tangent);
	}
	
	return YES;
}


- (void) priv_calculateBrokenTriangleAreas
{
	_haveTriangleAreas = YES;
	
	for (OOUInteger fIter = 0; fIter < _fileFaceCount; fIter++)
	{
		RawDATTriangle *triangle = &_rawTriangles[fIter];
		
		Vector v0 = triangle->position[0];
		Vector v1 = triangle->position[1];
		Vector v2 = triangle->position[2];
		
		/*	This is supposed to calculate areas using Heron's formula, but doesn't.
			(The *0.25 is supposed to be outside the sqrt.) Bugwards-compatibility
			is in effect.
		*/
		float a2 = distance2(v0, v1);
		float b2 = distance2(v1, v2);
		float c2 = distance2(v2, v0);
		triangle->area = sqrtf(2.0 * (a2 * b2 + b2 * c2 + c2 * a2) - 0.25 * (a2 * a2 + b2 * b2 +c2 * c2));
	}
}


- (void) priv_calculateCorrectTriangleAreas
{
	_haveTriangleAreas = YES;
	
	for (OOUInteger fIter = 0; fIter < _fileFaceCount; fIter++)
	{
		RawDATTriangle *triangle = &_rawTriangles[fIter];
		
		/*	Calculate area of triangle.
			The magnitude of the cross product of two vectors is the area of
			the parallelogram they span. The area of a triangle is half the
			area of a parallelogram sharing two of its sides.
			Since we only use the area of the triangle as a weight factor,
			constant terms are irrelevant, so we don't bother halving the
			value.
		*/
		Vector AB = vector_subtract(triangle->position[1], triangle->position[0]);
		Vector AC = vector_subtract(triangle->position[2], triangle->position[0]);
		triangle->area = magnitude(true_cross_product(AB, AC));
	}
}


- (BOOL) priv_calculateVertexNormalsAndTangents
{
	if (_brokenSmoothing)
	{
		[self priv_calculateBrokenTriangleAreas];
	}
	else
	{
		[self priv_calculateCorrectTriangleAreas];
	}

	
	for (OOUInteger vIter = 0; vIter < _fileVertexCount; vIter++)
	{
		NSAutoreleasePool *pool = [NSAutoreleasePool new];
		
		Vector normalSum = kZeroVector;
		Vector tangentSum = kZeroVector;
		
		VertexFaceRef *vfr = &_faceRefs[vIter];
		OOUInteger fIter, fCount = VFRGetCount(vfr);
		for (fIter = 0; fIter < fCount; fIter++)
		{
			RawDATTriangle *triangle = &_rawTriangles[VFRGetFaceAtIndex(vfr, fIter)];
			
			normalSum = vector_add(normalSum, vector_multiply_scalar(triangle->normal, triangle->area));
			tangentSum = vector_add(tangentSum, vector_multiply_scalar(triangle->tangent, triangle->area));
		}
		
		normalSum = vector_normal_or_fallback(normalSum, kBasisZVector);
		tangentSum = vector_normal_or_fallback(tangentSum, kBasisXVector);
		CleanVector(&normalSum);
		CleanVector(&tangentSum);
		NSDictionary *attrs = $dict(kOOMNormalAttributeKey, OOMArrayFromVector(normalSum), kOOMTangentAttributeKey, OOMArrayFromVector(tangentSum));
		_fileVertices[vIter] = [[_fileVertices[vIter] vertexByAddingAttributes:attrs] retain];
		
		[pool drain];
		[_fileVertices[vIter] autorelease];	// Needs to be autoreleased in outer pool.
	}
	
	return YES;
}


/*	This is conceptually broken.
	At the moment, it's calculating one tangent per "input" vertex. It should
	be calculating one tangent per "real" vertex, where a "real" vertex is
	defined as a combination of position, normal, material and texture
	coordinates.
	Currently, we don't have a format with unique "real" vertices.
	This basically means explicit-normal models without explicit tangents
	can't usefully be normal mapped.
*/
- (BOOL) priv_calculateVertexTangents
{
	//	Oolite gets area calculation right in this case.
	[self priv_calculateCorrectTriangleAreas];
	
	for (OOUInteger vIter = 0; vIter < _fileVertexCount; vIter++)
	{
		NSAutoreleasePool *pool = [NSAutoreleasePool new];
		
		Vector tangentSum = kZeroVector;
		
		VertexFaceRef *vfr = &_faceRefs[vIter];
		OOUInteger fIter, fCount = VFRGetCount(vfr);
		for (fIter = 0; fIter < fCount; fIter++)
		{
			RawDATTriangle *triangle = &_rawTriangles[VFRGetFaceAtIndex(vfr, fIter)];
			
			tangentSum = vector_add(tangentSum, vector_multiply_scalar(triangle->tangent, triangle->area));
		}
		
		tangentSum = vector_normal_or_fallback(tangentSum, kBasisXVector);
		CleanVector(&tangentSum);
		_fileVertices[vIter] = [[_fileVertices[vIter] vertexByAddingAttribute:OOMArrayFromVector(tangentSum)
																	   forKey:kOOMTangentAttributeKey] retain];
		
		[pool drain];
		[_fileVertices[vIter] autorelease];	// Needs to be autoreleased in outer pool.
	}
	
	return YES;
}


- (void) priv_calculateSmoothGroupEdgeNormal:(Vector *)outNormal
								  andTangent:(Vector *)outTangent
								   forVertex:(OOUInteger)vi
							   inSmoothGroup:(uint16_t)smoothGroup
{
	NSParameterAssert(outNormal != NULL && outTangent != NULL);
	NSAssert(_haveTriangleAreas, @"Expected areas to have been calculated by now.");
	
	Vector normalSum = kZeroVector;
	Vector tangentSum = kZeroVector;
	
	VertexFaceRef *vfr = &_faceRefs[vi];
	OOUInteger fIter, fCount = VFRGetCount(vfr);
	for (fIter = 0; fIter < fCount; fIter++)
	{
		RawDATTriangle *triangle = &_rawTriangles[VFRGetFaceAtIndex(vfr, fIter)];
		if (triangle->smoothGroup == smoothGroup)
		{
			normalSum = vector_add(normalSum, vector_multiply_scalar(triangle->normal, triangle->area));
			tangentSum = vector_add(tangentSum, vector_multiply_scalar(triangle->tangent, triangle->area));			
		}
	}
	
	CleanVector(&normalSum);
	CleanVector(&tangentSum);
	*outNormal = vector_normal_or_fallback(normalSum, kBasisZVector);
	*outTangent = vector_normal_or_fallback(tangentSum, kBasisXVector);
}


- (BOOL) priv_buildGroups
{
	OOUInteger vIter, fIter, mIter;
	BOOL isEdgeVertex[_fileVertexCount];
	BOOL seenSmoothGroup[_fileVertexCount];
	memset(seenSmoothGroup, 0, sizeof seenSmoothGroup);
	
	if (_usesSmoothGroups)
	{
		/*	Find any vertices that are between faces of different smoothing
			groups, and mark them as being on an edge and thus not smoothed.
		*/
		for (fIter = 0; fIter < _fileFaceCount; fIter++)
		{
			uint16_t smoothGroup = _rawTriangles[fIter].smoothGroup;
			for (vIter = 0; vIter < 3; vIter++)
			{
				OOUInteger vi = _rawTriangles[fIter].vertex[vIter];
				if (seenSmoothGroup[vi] == 0)
				{
					// Not seen this smooth group before.
					seenSmoothGroup[vi] = smoothGroup;
				}
				else if (seenSmoothGroup[vi] != smoothGroup)
				{
					// Vertex is on boundary between smooth groups.
					isEdgeVertex[vi] = YES;
				}
			}
		}
	}
	
	NSMutableSet *uniquedVertices = [NSMutableSet set];
	_mesh = [OOMMesh new];
	
	/*	This is technically O(n * m) where n is face count and m is material
		count, but given that m is small on any practical model (Oolite 1.x
		doesn't allow more than 7) it's not a big deal.
	*/
	for (mIter = 0; mIter < _materialCount; mIter++)
	{
		OOMFaceGroup *faceGroup = [OOMFaceGroup new];
		[faceGroup setName:[_materialKeys objectAtIndex:mIter]];
		
		for (fIter = 0; fIter < _fileFaceCount; fIter++)
		{
			NSAutoreleasePool *pool = [NSAutoreleasePool new];
			
			RawDATTriangle *triangle = &_rawTriangles[fIter];
			if (triangle->materialIndex == mIter)
			{
				OOMVertex *triVertices[3];
				
				for (vIter = 0; vIter < 3; vIter++)
				{
					OOUInteger vi = triangle->vertex[vIter];
					OOMVertex *vertex = nil;
					
					if (_smoothing)
					{
						if (_usesSmoothGroups && isEdgeVertex[vi])
						{
							// Handle edge vertices.
							Vector normal, tangent;
							[self priv_calculateSmoothGroupEdgeNormal:&normal
														   andTangent:&tangent
															forVertex:vi
														inSmoothGroup:triangle->smoothGroup];
							vertex = [_fileVertices[vi] vertexByAddingAttributes:$dict(kOOMNormalAttributeKey, OOMArrayFromVector(normal), kOOMTangentAttributeKey, OOMArrayFromVector(tangent))];
						}
						else
						{
							// Vertex is already smoothed.
							vertex = _fileVertices[vi];
							NSAssert([vertex attributeForKey:kOOMNormalAttributeKey] != nil && [vertex attributeForKey:kOOMTangentAttributeKey] != nil, @"Smoothed vertices should have normals and tangents by now.");
						}
					}
					else
					{
						// No smoothing.
						vertex = [_fileVertices[vi] vertexByAddingAttributes:$dict(kOOMNormalAttributeKey, OOMArrayFromVector(triangle->normal), kOOMTangentAttributeKey, OOMArrayFromVector(triangle->tangent))];
					}
					
					// Add in texture coordinate.
					vertex = [vertex vertexByAddingAttribute:OOMArrayFromVector2D(triangle->texCoords[vIter])
													  forKey:kOOMTexCoordsAttributeKey];
					
					// Save uniqued vertex. Slow!
					triVertices[vIter] = [uniquedVertices member:vertex];
					if (triVertices[vIter] == nil)
					{
						[uniquedVertices addObject:vertex];
						triVertices[vIter] = vertex;
					}
				}
				
				[faceGroup addFace:[OOMFace faceWithVertices:triVertices]];
			}
			[pool drain];
		}
		
		[_mesh addFaceGroup:faceGroup];
		[faceGroup release];
	}
	
	return YES;
}


- (void) priv_dumpDAT
{
	NSString *path = [[_path stringByDeletingPathExtension] stringByAppendingString:@"_debugdump.dat"];
	FILE *file = fopen([path UTF8String], "w");
	if (file == NULL)
	{
		OOMReportInfo(_issues, @"writeFailed", @"Could not open debug dump file %@", path);
		return;
	}
	
	fprintf(file, "// Debug dump of %s\n\nNVERTS %lu\nNFACES %lu\n\n\nVERTEX\n", [[_path lastPathComponent] UTF8String], (unsigned long)_fileVertexCount, (unsigned long)_fileFaceCount);
	
	for (OOUInteger vIter = 0; vIter < _fileVertexCount; vIter++)
	{
		Vector pos = [_fileVertices[vIter] position];
		fprintf(file, "%g %g %g\n", pos.x, pos.y, pos.z);
	}
	
	BOOL explicitNormals = _explicitNormals || _smoothing;
	
	fprintf(file, "\n\nFACES\n");
	for (OOUInteger fIter = 0; fIter < _fileFaceCount; fIter++)
	{
		RawDATTriangle *triangle = &_rawTriangles[fIter];
		Vector normal = explicitNormals ? kZeroVector : triangle->normal;
		OOUInteger smoothGroup = _usesSmoothGroups ? triangle->smoothGroup : 0;
		fprintf(file, "%lu 0 0 %g %g %g 3 %lu %lu %lu\n", (unsigned long)smoothGroup, normal.x, normal.y, normal.z, (unsigned long)triangle->vertex[0], (unsigned long)triangle->vertex[1], (unsigned long)triangle->vertex[2]);
	}
	
	if ([_materialKeys count] != 0)
	{
		fprintf(file, "\n\nTEXTURES\n");
		for (OOUInteger fIter = 0; fIter < _fileFaceCount; fIter++)
		{
			RawDATTriangle *triangle = &_rawTriangles[fIter];
			fprintf(file, "%u 1 1 %g %g %g %g %g %g\n", triangle->materialIndex,
					triangle->texCoords[0].x, triangle->texCoords[0].y,
					triangle->texCoords[1].x, triangle->texCoords[1].y,
					triangle->texCoords[2].x, triangle->texCoords[2].y);
		}
		
		fprintf(file, "\n\nNAMES %lu\n", (unsigned long)_materialCount);
		for (OOUInteger mIter = 0; mIter < _materialCount; mIter++)
		{
			fprintf(file, "%s\n", [[_materialKeys objectAtIndex:mIter] UTF8String]);
		}
	}
	
	if (explicitNormals)
	{
		fprintf(file, "\n\nNORMALS\n");
		for (OOUInteger vIter = 0; vIter < _fileVertexCount; vIter++)
		{
			Vector normal = [_fileVertices[vIter] normal];
			fprintf(file, "%g %g %g\n", normal.x, normal.y, normal.z);
		}
		
		fprintf(file, "\n\nTANGENTS\n");
		for (OOUInteger vIter = 0; vIter < _fileVertexCount; vIter++)
		{
			Vector tangent = [_fileVertices[vIter] tangent];
			fprintf(file, "%g %g %g\n", tangent.x, tangent.y, tangent.z);
		}
	}
	
	fprintf(file, "\nEND\n");
}

@end


static void VFRAddFace(VertexFaceRef *vfr, OOUInteger index)
{
	NSCParameterAssert(vfr != NULL);
	
	if (index < UINT16_MAX && vfr->internCount < kVertexFaceDefInternalCount)
	{
		vfr->internFaces[vfr->internCount++] = index;
	}
	else
	{
		if (vfr->extra == nil)  vfr->extra = [[NSMutableArray alloc] init];
		[vfr->extra addObject:$int(index)];
	}
}


static OOUInteger VFRGetCount(VertexFaceRef *vfr)
{
	NSCParameterAssert(vfr != NULL);
	
	return vfr->internCount + [vfr->extra count];
}


static OOUInteger VFRGetFaceAtIndex(VertexFaceRef *vfr, OOUInteger index)
{
	NSCParameterAssert(vfr != NULL && index < VFRGetCount(vfr));
	
	if (index < vfr->internCount)  return vfr->internFaces[index];
	else  return [vfr->extra oo_unsignedIntegerAtIndex:index - vfr->internCount];
}


static void VFRRelease(VertexFaceRef *vfr)
{
	NSCParameterAssert(vfr != NULL);
	
	[vfr->extra release];
}
