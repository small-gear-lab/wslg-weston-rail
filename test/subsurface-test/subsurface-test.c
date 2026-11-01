// Test client for the RAIL shell: a toplevel with a black single-pixel buffer (viewport-scaled) that is completely
// covered by a subsurface with the real content, the way a nested KWin draws. Waits for a frame callback on the
// toplevel. Modes: 0 = desync subsurface, 1 = plain shm toplevel, 2 = sync subsurface (the default of the protocol).
#define _GNU_SOURCE
#include <stdlib.h>
// Mimics KWin's nested backend: toplevel with a black single-pixel buffer + viewport, content in a subsurface.
#include <wayland-client.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdint.h>
#include <sys/mman.h>
#include "xdg-shell.h"
#include "viewporter.h"
#include "single-pixel-buffer-v1.h"
static struct wl_compositor*comp; static struct wl_subcompositor*subc; static struct wl_shm*shm;
static struct xdg_wm_base*wm; static struct wp_viewporter*vp; static struct wp_single_pixel_buffer_manager_v1*spb;
static void reg(void*d,struct wl_registry*r,uint32_t n,const char*i,uint32_t v){
 if(!strcmp(i,"wl_compositor"))comp=wl_registry_bind(r,n,&wl_compositor_interface,4);
 else if(!strcmp(i,"wl_subcompositor"))subc=wl_registry_bind(r,n,&wl_subcompositor_interface,1);
 else if(!strcmp(i,"wl_shm"))shm=wl_registry_bind(r,n,&wl_shm_interface,1);
 else if(!strcmp(i,"xdg_wm_base"))wm=wl_registry_bind(r,n,&xdg_wm_base_interface,1);
 else if(!strcmp(i,"wp_viewporter"))vp=wl_registry_bind(r,n,&wp_viewporter_interface,1);
 else if(!strcmp(i,"wp_single_pixel_buffer_manager_v1"))spb=wl_registry_bind(r,n,&wp_single_pixel_buffer_manager_v1_interface,1);}
static void rem(void*d,struct wl_registry*r,uint32_t n){}
static const struct wl_registry_listener rl={reg,rem};
static void ping(void*d,struct xdg_wm_base*w,uint32_t s){xdg_wm_base_pong(w,s);}
static const struct xdg_wm_base_listener wl={ping};
static int ndone; static void cbdone(void*d,struct wl_callback*c,uint32_t t){ndone++;fprintf(stderr,"frame done #%d (%s)\n",ndone,(char*)d);}
static const struct wl_callback_listener cbl={cbdone};
static int configured; static void xc(void*d,struct xdg_surface*s,uint32_t ser){xdg_surface_ack_configure(s,ser);configured=1;}
static const struct xdg_surface_listener xl={xc};
static void tc(void*d,struct xdg_toplevel*t,int32_t w,int32_t h,struct wl_array*s){} static void tcl(void*d,struct xdg_toplevel*t){}
static const struct xdg_toplevel_listener tl={tc,tcl};
int main(int argc,char**argv){
 int W=400,H=300; int mode=argc>1?atoi(argv[1]):0; /* 0=KWin-like, 1=plain shm toplevel */
 struct wl_display*dp=wl_display_connect(NULL); struct wl_registry*r=wl_display_get_registry(dp);
 wl_registry_add_listener(r,&rl,NULL); wl_display_roundtrip(dp);
 xdg_wm_base_add_listener(wm,&wl,NULL);
 struct wl_surface*s=wl_compositor_create_surface(comp);
 struct xdg_surface*xs=xdg_wm_base_get_xdg_surface(wm,s); xdg_surface_add_listener(xs,&xl,NULL);
 struct xdg_toplevel*tp=xdg_surface_get_toplevel(xs); xdg_toplevel_add_listener(tp,&tl,NULL);
 xdg_toplevel_set_title(tp,"subsurface-test"); xdg_toplevel_set_app_id(tp,"subsurface-test");
 wl_surface_commit(s); while(!configured)wl_display_roundtrip(dp);
 int fd=memfd_create("b",0); ftruncate(fd,W*H*4); uint32_t*px=mmap(0,W*H*4,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
 for(int y=0;y<H;y++)for(int x=0;x<W;x++)px[y*W+x]=0xff000000|((x*255/W)<<16)|((y*255/H)<<8)|0x40;
 struct wl_shm_pool*pool=wl_shm_create_pool(shm,fd,W*H*4); struct wl_buffer*b=wl_shm_pool_create_buffer(pool,0,W,H,W*4,WL_SHM_FORMAT_XRGB8888);
 if(mode==1){ wl_surface_attach(s,b,0,0); wl_surface_damage_buffer(s,0,0,W,H); wl_surface_commit(s); }
 else {
  struct wl_surface*cs=wl_compositor_create_surface(comp); struct wl_subsurface*ss=wl_subcompositor_get_subsurface(subc,cs,s);
  if(mode!=2) wl_subsurface_set_desync(ss);
  wl_surface_attach(cs,b,0,0); wl_surface_damage_buffer(cs,0,0,W,H); wl_surface_commit(cs);
  struct wl_buffer*sb=wp_single_pixel_buffer_manager_v1_create_u32_rgba_buffer(spb,0,0,0,0xffffffffu);
  struct wp_viewport*v=wp_viewporter_get_viewport(vp,s); wp_viewport_set_destination(v,W,H);
  wl_surface_attach(s,sb,0,0); wl_surface_damage_buffer(s,0,0,1,1); wl_surface_commit(s);
 }
 struct wl_callback*cb=wl_surface_frame(s); wl_callback_add_listener(cb,&cbl,"parent"); wl_surface_commit(s);
 fprintf(stderr,"mode %d running, waiting for frame callback on the toplevel\n",mode);
 while(wl_display_dispatch(dp)!=-1); return 0;}
