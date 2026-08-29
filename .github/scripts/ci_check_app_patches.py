import os, json, zipfile, hashlib, re, subprocess, glob
import urllib.request

def get_app_mappings():
    apps_stable = {}
    apps_dev = {}
    cli_sources = {}
    
    toml_files = sorted(glob.glob('configs/patches/*.toml'))
    for toml_file in toml_files:
        is_stable_only = toml_file.endswith('.stable.toml')
        is_dev_only = toml_file.endswith('.dev.toml')
        with open(toml_file, 'r', encoding='utf-8') as f:
            content = f.read()
            # Split by [app_key]
            sections = re.split(r'^\[(.*?)\]\s*$', content, flags=re.MULTILINE)[1:]
            for i in range(0, len(sections), 2):
                key = sections[i].strip()
                body = sections[i+1]
                
                m_enabled = re.search(r'^enabled\s*=\s*(true|false)', body, flags=re.MULTILINE | re.IGNORECASE)
                m_stable = re.search(r'^enabledStable\s*=\s*(true|false)', body, flags=re.MULTILINE | re.IGNORECASE)
                m_dev = re.search(r'^enabledDev\s*=\s*(true|false)', body, flags=re.MULTILINE | re.IGNORECASE)
                m_pver = re.search(r'patches-version\s*=\s*"([^"]+)"', body, flags=re.MULTILINE | re.IGNORECASE)
                m_cver = re.search(r'cli-version\s*=\s*"([^"]+)"', body, flags=re.MULTILINE | re.IGNORECASE)

                pver = m_pver.group(1).lower() if m_pver else ""
                cver = m_cver.group(1).lower() if m_cver else ""
                has_dev_ver = pver in ["dev", "absolutelatest"] or cver in ["dev", "absolutelatest"]

                enabled = m_enabled.group(1).lower() == 'true' if m_enabled else True
                enabledStable = m_stable.group(1).lower() == 'true' if m_stable else (not is_dev_only and not has_dev_ver)
                enabledDev = m_dev.group(1).lower() == 'true' if m_dev else (not is_stable_only or has_dev_ver)
                
                if not enabled:
                    continue
                
                # Extract patches-source
                m_src = re.search(r'patches-source\s*=\s*"([^"]+)"', body)
                src = m_src.group(1).lower() if m_src else "morpheapp/morphe-patches"
                
                # Extract cli-source
                m_cli = re.search(r'cli-source\s*=\s*"([^"]+)"', body)
                cli_src = m_cli.group(1).lower() if m_cli else "morpheapp/morphe-desktop"
                if cli_src:
                    cli_sources.setdefault(src, set()).add(cli_src)
                
                m_pkg = re.search(r'pkg-name\s*=\s*"([^"]+)"', body)
                pkg_name = m_pkg.group(1) if m_pkg else ''
                
                m_app = re.search(r'app-name\s*=\s*"([^"]+)"', body)
                app_name = m_app.group(1).lower() if m_app else ''
                
                m_pf = re.search(r'patch-folder\s*=\s*"([^"]+)"', body)
                patch_folder = m_pf.group(1).lower() if m_pf else ''
                
                if not pkg_name:
                    m_git = re.search(r'github-dlurl\s*=\s*"([^"]+)"', body)
                    m_arch = re.search(r'archive-dlurl\s*=\s*"([^"]+)"', body)
                    if m_git and 'releases/tag/' in m_git.group(1):
                        pkg_name = m_git.group(1).rstrip('/').split('/')[-1]
                    elif m_arch and 'apks/' in m_arch.group(1):
                        pkg_name = m_arch.group(1).rstrip('/').split('/')[-1]
                
                if pkg_name:
                    if enabledStable:
                        apps_stable.setdefault(src, {})[key] = {'pkg': pkg_name, 'app_name': app_name, 'patch_folder': patch_folder}
                    if enabledDev:
                        apps_dev.setdefault(src, {})[key] = {'pkg': pkg_name, 'app_name': app_name, 'patch_folder': patch_folder}

    return apps_stable, apps_dev, cli_sources

def process_zip(path, pkg_info):
    pkgs = list(pkg_info.keys())
    pkg_bytes = {p: p.encode() for p in pkgs}
    buckets = {p: hashlib.md5() for p in pkgs + ['shared']}
    comp_map = {}
    all_comps = set()
    
    with zipfile.ZipFile(path) as z:
        # Pass 1: Build all_comps
        for info in z.infolist():
            m = re.search(r'(?:^|/)(?:patches|patched_up)/([^/]+)/', info.filename)
            if m:
                comp = m.group(1)
                if comp not in ['shared', 'all']:
                    all_comps.add(comp)
                    
        # Inject explicitly defined patch-folders from config so they are evaluated even if the regex above missed them
        for meta in pkg_info.values():
            pf_str = meta.get('patch_folder', '')
            if pf_str:
                for pf in pf_str.split():
                    if pf != '*':
                        all_comps.add(pf)
                        
        # Pass 2: Heuristics
        for comp in all_comps:
            for pkg, meta in pkg_info.items():
                pf_str = meta.get('patch_folder', '')
                an = meta.get('app_name', '')
                an_clean = an.replace('-', '')
                
                if pf_str:
                    pfs = pf_str.split()
                    if '*' in pfs or comp in pfs:
                        comp_map.setdefault(comp, set()).add(pkg)
                    continue
                    
                if an and (comp == an or comp == an_clean):
                    comp_map.setdefault(comp, set()).add(pkg)
                elif pkg and comp in pkg.split('.'):
                    # Prevent youtube from mapping to youtube-music
                    if comp == 'youtube' and 'music' in an.lower(): continue
                    comp_map.setdefault(comp, set()).add(pkg)
            
        # Pass 3: Bytecode Fallback
        for info in z.infolist():
            if info.filename.endswith('.class'):
                content = z.read(info)
                for pkg, b_pkg in pkg_bytes.items():
                    pf = pkg_info[pkg].get('patch_folder', '')
                    if pf: continue # Explicitly defined patch-folders shouldn't use bytecode fallback
                    
                    if b_pkg in content:
                        m = re.search(r'(?:^|/)(?:patches|patched_up)/([^/]+)/', info.filename)
                        if m:
                            comp = m.group(1)
                            if comp not in ['shared', 'all']:
                                comp_map.setdefault(comp, set()).add(pkg)

        comp_regexes = {comp: re.compile(r'(^|/)' + re.escape(comp) + r'(/|\.|-)') for comp in all_comps}
                    
        for info in sorted(z.infolist(), key=lambda x: x.filename):
            if info.is_dir(): continue
            if info.filename.startswith('META-INF/') or info.filename == 'classes.dex':
                continue
                
            content = z.read(info)
            
            # Wildcard catch-all: if an app uses '*', hash EVERYTHING for it
            for pkg in pkgs:
                pf_str = pkg_info[pkg].get('patch_folder', '')
                if pf_str and '*' in pf_str.split():
                    buckets[pkg].update(content)
                    
            assigned = False
            # 1. Directory Structure matching (Primary source of truth)
            for comp, reg in comp_regexes.items():
                if reg.search(info.filename):
                    if comp in comp_map:
                        for p in comp_map[comp]:
                            buckets[p].update(content)
                    assigned = True # Mark as handled to avoid shared bucket poisoning
                    break
                    
            # 2. Bytecode Fallback (For isolated patches or shared/ folders)
            if not assigned:
                for pkg, b_pkg in pkg_bytes.items():
                    if b_pkg in content:
                        buckets[pkg].update(content)
                        assigned = True
                        break
                        
            if not assigned:
                buckets['shared'].update(content)
    return {k: v.hexdigest() for k, v in buckets.items()}

def evaluate_repo_channel(repo_lower, repo, tag, channel, new_info, hashes, active_list, apps_stable, apps_dev, is_revanced_or_morphe):
    repo_apps = apps_stable.get(repo_lower, {}) if channel == 'stable' else apps_dev.get(repo_lower, {})
    if not repo_apps:
        print(f"::notice::No enabled apps found for {repo} ({channel}). Skipping.")
        return

    # Hash matching disabled: trigger all apps for this repo whenever the tag changes
    print(f"Tag changed for {repo} ({channel}). Triggering all apps (hash matching disabled).")
    active_list.extend(repo_apps.keys())


def run():
    try:
        with open('tags_old.json', 'r') as f:
            tags_old = json.load(f)
    except FileNotFoundError:
        tags_old = {}
        
    try:
        with open('tags_new.json', 'r') as f:
            tags_new = json.load(f)
    except FileNotFoundError:
        tags_new = {}
    
    hash_file = 'configs/patch_file_hashes.json'
    if os.path.exists(hash_file):
        with open(hash_file, 'r') as f:
            hashes = json.load(f)
    else:
        hashes = {}

    apps_stable, apps_dev, cli_sources = get_app_mappings()
    
    active_stable = []
    active_dev = []

    for repo_key, new_info in tags_new.items():
        old_info = tags_old.get(repo_key, {})
        repo = new_info.get('repo', '')
        repo_lower = repo.lower()
        
        # Determine if we need to check stable/dev
        check_stable = new_info.get('stable') != "" and new_info.get('stable') != old_info.get('stable')
        check_dev = new_info.get('prerelease') != "" and new_info.get('prerelease') != old_info.get('prerelease')
        
        if new_info.get('enabled') is False:
            check_stable = False
            check_dev = False
        if new_info.get('enabledStable') is False:
            check_stable = False
        if new_info.get('enabledDev') is False:
            check_dev = False
        
        if not check_stable and not check_dev:
            continue
            
        repo_clis = cli_sources.get(repo_lower, set())
        
        is_revanced_or_morphe = any('revanced' in c or 'morphe' in c for c in repo_clis)
        if not repo_clis:
            is_revanced_or_morphe = True
        
        if repo_lower not in hashes:
            hashes[repo_lower] = {'stable': {}, 'dev': {}}
            
        if check_stable:
            evaluate_repo_channel(repo_lower, repo, new_info.get('stable'), 'stable', new_info, hashes, active_stable, apps_stable, apps_dev, is_revanced_or_morphe)
            
        if check_dev:
            evaluate_repo_channel(repo_lower, repo, new_info.get('prerelease'), 'dev', new_info, hashes, active_dev, apps_stable, apps_dev, is_revanced_or_morphe)

    with open(hash_file, 'w') as f:
        json.dump(hashes, f, indent=2, sort_keys=True)
        
    with open('active_patch_apps.stable.json', 'w') as f:
        json.dump(list(set(active_stable)), f)
        
    with open('active_patch_apps.dev.json', 'w') as f:
        json.dump(list(set(active_dev)), f)

if __name__ == '__main__':
    run()
