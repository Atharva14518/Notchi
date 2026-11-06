#!/usr/bin/env python3
"""Reproduce Notchi's LGPL-only universal executables with Xcode/clang + make.
No Homebrew libraries are linked. Source archives ship with the app. No GPL,
nonfree, version3, x264 or x265 options are enabled. Run from the repository.
"""
import hashlib, json, os, pathlib, shutil, subprocess, tarfile
SCRIPT = pathlib.Path(__file__).resolve()
BUNDLED = SCRIPT.parent.name == 'FFmpegSources'
ROOT = pathlib.Path.cwd() / 'NotchiMediaRebuild' if BUNDLED else SCRIPT.parent.parent
SOURCES = SCRIPT.parent if BUNDLED else ROOT / 'Resources/FFmpegSources'
(ROOT / 'Resources').mkdir(parents=True, exist_ok=True)
WORK = ROOT / 'build/FFmpegBuild'
SPECS = [
 ('ffmpeg-9.0.2.tar.xz','https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz','8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e','ffmpeg-9.0.2'),
 ('lame-3.100.tar.gz','https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz','ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e','lame-3.100'),
 ('libvpx-1.15.2.tar.gz','https://github.com/webmproject/libvpx/archive/refs/tags/v1.15.2.tar.gz','26fcd3db88045dee380e581862a6ef106f49b74b6396ee95c2993a260b4636aa','libvpx-1.15.2'),
 ('opus-1.5.2.tar.gz','https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz','65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1','opus-1.5.2')]
SDK = subprocess.check_output(['xcrun','--show-sdk-path'],text=True).strip()
JOBS = min(os.cpu_count() or 4, 8)
commands = []
def run(args, cwd, env=None):
    commands.append({'cwd':str(cwd.relative_to(WORK)), 'arguments':args})
    subprocess.run(args,cwd=cwd,env=env,check=True)
SOURCES.mkdir(parents=True,exist_ok=True); WORK.mkdir(parents=True,exist_ok=True)
for filename,url,digest,_ in SPECS:
    archive=SOURCES/filename
    if not archive.exists():
        cached=ROOT/'build/MediaSources'/filename
        if cached.exists(): shutil.copy2(cached,archive)
        else: subprocess.run(['curl','-fL','--retry','2',url,'-o',str(archive)],check=True)
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=digest: raise SystemExit('Source checksum mismatch: '+filename)
for arch,host in [('arm64','aarch64-apple-darwin'),('x86_64','x86_64-apple-darwin')]:
    base=WORK/arch; base.mkdir(exist_ok=True)
    prefix=base/'prefix'; prefix.mkdir(exist_ok=True)
    flags=f'-arch {arch} -isysroot {SDK} -mmacosx-version-min=14.0 -O2'
    env=os.environ.copy()
    env.update(CC='clang',CXX='clang++',CFLAGS=flags,CXXFLAGS=flags,LDFLAGS=flags,
               PKG_CONFIG_PATH='',PKG_CONFIG_LIBDIR=str(prefix/'lib/pkgconfig'),MACOSX_DEPLOYMENT_TARGET='14.0')
    for filename,_,_,folder in SPECS:
        source=base/folder
        if not source.exists():
            with tarfile.open(SOURCES/filename) as archive: archive.extractall(base,filter='data')
    # No external assembler required; generic libvpx C code is portable to both slices.
    for name,args in [
        ('lame-3.100',[f'--host={host}',f'--prefix={prefix}','--disable-shared','--enable-static','--disable-frontend','--disable-asm']),
        ('opus-1.5.2',[f'--host={host}',f'--prefix={prefix}','--disable-shared','--enable-static','--disable-doc','--disable-extra-programs']),
        ('libvpx-1.15.2',[f'--prefix={prefix}','--target=generic-gnu','--disable-shared','--enable-static','--disable-examples','--disable-tools','--disable-docs','--disable-unit-tests'])]:
        source=base/name
        stamp=source/'.notchi-built'
        if not stamp.exists():
            depenv=env.copy()
            if name.startswith('libvpx'): depenv['CC']='clang '+flags; depenv['CXX']='clang++ '+flags
            run(['./configure']+args,source,depenv)
            run(['make',f'-j{JOBS}'],source,depenv); run(['make','install'],source,depenv); stamp.touch()
    source=base/'ffmpeg-9.0.2'
    if not (source/'.notchi-built').exists():
        args=['./configure',f'--prefix={prefix}',f'--arch={arch}','--target-os=darwin','--enable-cross-compile',
              '--cc=clang',f'--extra-cflags={flags} -I{prefix}/include',f'--extra-ldflags={flags} -L{prefix}/lib',
              '--pkg-config-flags=--static','--disable-autodetect','--disable-gpl','--disable-nonfree','--disable-version3',
              '--disable-shared','--enable-static','--disable-doc','--disable-debug','--disable-ffplay',
              '--disable-x86asm','--enable-videotoolbox','--enable-audiotoolbox','--enable-libmp3lame','--enable-libvpx','--enable-libopus',
              '--disable-network','--disable-indevs','--disable-outdevs','--enable-pthreads']
        run(args,source,env); run(['make',f'-j{JOBS}'],source,env); (source/'.notchi-built').touch()
for tool in ['ffmpeg','ffprobe']:
    target=ROOT/'Resources'/tool
    subprocess.run(['lipo','-create',str(WORK/'arm64/ffmpeg-9.0.2'/tool),str(WORK/'x86_64/ffmpeg-9.0.2'/tool),'-output',str(target)],check=True)
    target.chmod(0o755)
licenses=ROOT/'Resources/FFmpegLicenses'
licenses.mkdir(exist_ok=True)
for source,filename,target in [('ffmpeg-9.0.2','COPYING.LGPLv2.1','FFmpeg-LGPL-2.1.txt'),('ffmpeg-9.0.2','LICENSE.md','FFmpeg-LICENSE.md'),('lame-3.100','COPYING','LAME-LGPL.txt'),('libvpx-1.15.2','LICENSE','libvpx-BSD.txt'),('libvpx-1.15.2','PATENTS','libvpx-PATENTS.txt'),('opus-1.5.2','COPYING','Opus-BSD.txt')]:
    shutil.copy2(WORK/'arm64'/source/filename, licenses/target)
manifest={'sources':[{'archive':a,'url':u,'sha256':h} for a,u,h,_ in SPECS], 'commands':commands,'modified_sources':False,'deployment_target':'14.0','architectures':['arm64','x86_64']}
output_sources = ROOT / 'Resources/FFmpegSources'
output_sources.mkdir(parents=True, exist_ok=True)
for filename,_,_,_ in SPECS:
    if (SOURCES/filename).resolve() != (output_sources/filename).resolve(): shutil.copy2(SOURCES/filename, output_sources/filename)
(output_sources/'BUILD_MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
if SCRIPT != (output_sources/'build_ffmpeg.py').resolve(): shutil.copy2(SCRIPT,output_sources/'build_ffmpeg.py')
print('Universal LGPL-only FFmpeg + ffprobe built in Resources.',flush=True)
