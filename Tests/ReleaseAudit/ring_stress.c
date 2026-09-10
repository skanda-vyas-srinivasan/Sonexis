#include "RealtimeAudioRing.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <pthread.h>
#include <sched.h>
static unsigned seed=210;
static unsigned next(void){seed=seed*1664525u+1013904223u;return seed;}
static SonexisAudioRingBuffer *threadRing;
static const unsigned total=2000000;
static void *producer(void *unused){
 unsigned pos=0; float in[514];
 while(pos<total){unsigned n=total-pos<257?total-pos:257; for(unsigned i=0;i<n;i++){in[i*2]=(float)((pos+i)%1000)/1000;in[i*2+1]=-in[i*2];}
  unsigned written=SonexisAudioRingBufferWriteInterleaved(threadRing,in,n);pos+=written;if(!written)sched_yield();}
 return NULL;
}
int main(void){
 unsigned long long checked=0;
 for(unsigned channels=1;channels<=8;channels*=2){
  SonexisAudioRingBuffer *r=SonexisAudioRingBufferCreate(4096,channels);assert(r);
  float *queue=calloc(4096*channels,sizeof(float)),*in=calloc(5000*channels,sizeof(float)),*out=calloc(5000*channels,sizeof(float));
  unsigned head=0,count=0;unsigned long long dropped=0,under=0;
  for(unsigned k=0;k<20000;k++){
   unsigned n=next()%5000+1;
   if(next()&0x100){
    for(unsigned i=0;i<n*channels;i++)in[i]=(float)(next()%2001)/2000-0.5f;
    unsigned expected=n<4096-count?n:4096-count;
    unsigned actual=SonexisAudioRingBufferWriteInterleaved(r,in,n);assert(actual==expected);
    for(unsigned f=0;f<actual;f++)for(unsigned c=0;c<channels;c++)queue[((head+count+f)%4096)*channels+c]=in[f*channels+c];
    count+=actual;dropped+=n-actual;
   }else{
    unsigned expected=n<count?n:count;
    unsigned actual=SonexisAudioRingBufferReadInterleaved(r,out,n);assert(actual==expected);
    for(unsigned f=0;f<n;f++)for(unsigned c=0;c<channels;c++){float x=f<actual?queue[((head+f)%4096)*channels+c]:0;assert(out[f*channels+c]==x);checked++;}
    head=(head+actual)%4096;count-=actual;under+=n-actual;
   }
   assert(SonexisAudioRingBufferGetFillFrames(r)==count);
   assert(SonexisAudioRingBufferGetDroppedFrames(r)==dropped);
   assert(SonexisAudioRingBufferGetUnderflowFrames(r)==under);
  }
  free(queue);free(in);free(out);SonexisAudioRingBufferDestroy(r);
 }
 threadRing=SonexisAudioRingBufferCreate(4096,2);pthread_t thread;pthread_create(&thread,NULL,producer,NULL);
 unsigned pos=0;float out[386];
 while(pos<total){unsigned n=total-pos<193?total-pos:193;unsigned got=SonexisAudioRingBufferReadInterleaved(threadRing,out,n);
  for(unsigned i=0;i<got;i++){float x=(float)((pos+i)%1000)/1000;assert(out[2*i]==x && out[2*i+1]==-x);checked+=2;}pos+=got;if(!got)sched_yield();}
 pthread_join(thread,NULL);SonexisAudioRingBufferDestroy(threadRing);
 printf("PASS randomized wraparound/overflow/underflow, channels 1/2/4/8, 80,000 operations, %llu sample comparisons; concurrent 2,000,000-frame producer/consumer.\n",checked);
}
