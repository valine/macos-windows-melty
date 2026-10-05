#define GL_SILENCE_DEPRECATION
#import <AppKit/AppKit.h>
#import <OpenGL/gl.h>
#include <stdio.h>
#include <time.h>

typedef struct GLFWwindow GLFWwindow;
extern int glfwInit(void);
extern void glfwTerminate(void);
extern GLFWwindow *glfwCreateWindow(int,int,const char *,void *,GLFWwindow *);
extern void glfwMakeContextCurrent(GLFWwindow *);
extern void glfwSwapInterval(int);
extern void glfwSwapBuffers(GLFWwindow *);
extern void glfwPollEvents(void);
extern int glfwWindowShouldClose(GLFWwindow *);
extern void glfwGetWindowSize(GLFWwindow *,int *,int *);
extern void glfwGetFramebufferSize(GLFWwindow *,int *,int *);
extern NSWindow *glfwGetCocoaWindow(GLFWwindow *);
extern void *glfwSetWindowSizeCallback(GLFWwindow *,void (*)(GLFWwindow *,int,int));
extern void *glfwSetFramebufferSizeCallback(GLFWwindow *,void (*)(GLFWwindow *,int,int));
extern void *glfwSetWindowRefreshCallback(GLFWwindow *,void (*)(GLFWwindow *));

static FILE *logFile;
static int frameNumber, lastWidth, lastHeight;
static BOOL drawing;
static void trace(GLFWwindow *w, const char *event, int drawnWidth, int drawnHeight) {
    int ww, wh, fw, fh;
    glfwGetWindowSize(w,&ww,&wh);
    glfwGetFramebufferSize(w,&fw,&fh);
    NSWindow *n=glfwGetCocoaWindow(w);
    NSRect content=n.contentView.bounds;
    NSRect backing=[n.contentView convertRectToBacking:content];
    fprintf(logFile,"%.6f %s frame=%d live=%d outer=%.0fx%.0f native=%.0fx%.0f backing=%.0fx%.0f glfw=%dx%d framebuffer=%dx%d drawn=%dx%d previous=%dx%d\n",
        NSProcessInfo.processInfo.systemUptime,event,frameNumber,n.inLiveResize,
        n.frame.size.width,n.frame.size.height,content.size.width,content.size.height,
        backing.size.width,backing.size.height,ww,wh,fw,fh,drawnWidth,drawnHeight,lastWidth,lastHeight);
    fflush(logFile);
}
static void draw(GLFWwindow *w) {
    if(drawing) return;
    drawing=YES;
    int fw,fh;
    glfwGetFramebufferSize(w,&fw,&fh);
    if(fw>0 && fh>0) {
        frameNumber++;
        glViewport(0,0,fw,fh);
        glMatrixMode(GL_PROJECTION); glLoadIdentity(); glOrtho(0,fw,0,fh,-1,1);
        glMatrixMode(GL_MODELVIEW); glLoadIdentity();
        glClearColor(0.12,0.14,0.18,1); glClear(GL_COLOR_BUFFER_BIT);
        glColor3f(0.3,0.7,0.8);
        glBegin(GL_LINES);
        for(int x=0;x<fw;x+=40) { glVertex2i(x,0); glVertex2i(x,fh); }
        for(int y=0;y<fh;y+=40) { glVertex2i(0,y); glVertex2i(fw,y); }
        glEnd();
        glColor3f(1,0.5,0.2);
        glBegin(GL_LINE_LOOP);
        glVertex2i(fw/2-100,fh/2-100); glVertex2i(fw/2+100,fh/2-100);
        glVertex2i(fw/2+100,fh/2+100); glVertex2i(fw/2-100,fh/2+100);
        glEnd();
        if(fw!=lastWidth || fh!=lastHeight) trace(w,"before-swap",fw,fh);
        glfwSwapBuffers(w);
        if(fw!=lastWidth || fh!=lastHeight) trace(w,"after-swap",fw,fh);
        lastWidth=fw; lastHeight=fh;
    }
    drawing=NO;
}
static void sizeChanged(GLFWwindow *w,int width,int height) {
    trace(w,"window-size",width,height);
}
static void framebufferChanged(GLFWwindow *w,int width,int height) { trace(w,"framebuffer-size",width,height); }
static void refreshed(GLFWwindow *w) { trace(w,"refresh",0,0); draw(w); }

int main(void) {
    @autoreleasepool {
        NSString *path=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/Melty GLFW Resize Probe.log"];
        logFile=fopen(path.fileSystemRepresentation,"w");
        if(!logFile || !glfwInit()) return 1;
        GLFWwindow *w=glfwCreateWindow(800,540,"GLFW Resize Probe",NULL,NULL);
        if(!w) return 2;
        glfwMakeContextCurrent(w); glfwSwapInterval(1);
        glfwSetWindowSizeCallback(w,sizeChanged);
        glfwSetFramebufferSizeCallback(w,framebufferChanged);
        glfwSetWindowRefreshCallback(w,refreshed);
        trace(w,"start",0,0);
        while(!glfwWindowShouldClose(w)) {
            @autoreleasepool { glfwPollEvents(); draw(w); }
        }
        glfwTerminate(); fclose(logFile);
    }
    return 0;
}
