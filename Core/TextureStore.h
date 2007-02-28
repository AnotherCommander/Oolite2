/*

TextureStore.m

Singleton responsible for loading, binding and caching textures.

For Oolite
Copyright (C) 2004  Giles C Williams

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#import <Foundation/Foundation.h>
#import "OOOpenGL.h"

#define OOLITE_EXCEPTION_TEXTURE_NOT_FOUND		@"OoliteTextureNotFoundException"
#define OOLITE_EXCEPTION_TEXTURE_NOT_UNDERSTOOD	@"OoliteTextureNotUnderstoodException"
#define OOLITE_EXCEPTION_FATAL					@"OoliteFatalException"


extern int debug;

@class OOColor;

@interface TextureStore : NSObject
{
}

+ (GLuint) maxTextureDimension;

+ (GLuint) getTextureNameFor:(NSString *)filename;
+ (GLuint) getImageNameFor:(NSString *)filename;
+ (GLuint) getTextureNameFor:(NSString *)filename inFolder:(NSString*) foldername;
+ (NSString*) getNameOfTextureWithGLuint:(GLuint) value;
+ (NSSize) getSizeOfTexture:(NSString *)filename;

#ifndef NO_SHADERS
//+ (GLuint) shaderProgramFromDictionary:(NSDictionary *) shaderDict;
+ (GLhandleARB) shaderProgramFromDictionary:(NSDictionary *) shaderDict;
#endif

+ (void) reloadTextures;

// routines to create textures...

+ (GLuint) getPlanetTextureNameFor:(NSDictionary*)planetinfo intoData:(unsigned char **)textureData;
+ (GLuint) getPlanetNormalMapNameFor:(NSDictionary*)planetinfo intoData:(unsigned char **)textureData;
+ (GLuint) getCloudTextureNameFor:(OOColor*) color: (GLfloat) impress: (GLfloat) bias intoData:(unsigned char **)textureData;

void fillRanNoiseBuffer();

void fillSquareImageDataWithBlur(unsigned char * imageBuffer, int width, int nplanes);

void addNoise(float * buffer, int p, int n, float scale);
void fillSquareImageDataWithSmoothNoise(unsigned char * imageBuffer, int width, int nplanes);
void fillSquareImageDataWithCloudTexture(unsigned char * imageBuffer, int width, int nplanes, OOColor* cloudcolor, float impress, float bias);
void fillSquareImageWithPlanetTex(unsigned char * imageBuffer, int width, int nplanes, float impress, float bias,
	OOColor* seaColor,
	OOColor* paleSeaColor,
	OOColor* landColor,
	OOColor* paleLandColor);
void fillSquareImageWithPlanetNMap(unsigned char * imageBuffer, int width, int nplanes, float impress, float bias, float factor);

@end
