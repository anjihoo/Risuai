<script lang="ts">
  import { onMount } from 'svelte';
  import { writable } from 'svelte/store';
  let username = '';
  let password = '';
  let otp = '';
  let error = '';
  let loading = false;
  let dark = writable(true);

  // 프리진다트 폰트 적용
  onMount(() => {
    const link = document.createElement('link');
    link.href = 'https://cdn.jsdelivr.net/gh/webfonthub/fontface@latest/FreeJinDot/FreeJinDot.css';
    link.rel = 'stylesheet';
    document.head.appendChild(link);
  });

  async function login() {
    loading = true;
    error = '';
    // 실제 인증 API 연동 필요
    // 예시: fetch('/api/login', { ... })
    setTimeout(() => {
      loading = false;
      if (password !== 'yourpassword' || otp !== '123456') {
        error = '로그인 정보가 올바르지 않습니다.';
      } else {
        // 성공 처리
        error = '';
        // ...
      }
    }, 1200);
  }
</script>

<style>
  :global(body) {
    font-family: 'FreeJinDot', sans-serif;
    background: var(--bg, #181a1b);
    color: var(--fg, #f5f5f5);
    transition: background 0.2s, color 0.2s;
  }
  .login-container {
    max-width: 400px;
    margin: 80px auto;
    padding: 32px 24px;
    border-radius: 16px;
    background: rgba(30,32,34,0.95);
    box-shadow: 0 4px 24px rgba(0,0,0,0.25);
    display: flex;
    flex-direction: column;
    gap: 18px;
  }
  .login-title {
    font-size: 2rem;
    font-weight: bold;
    text-align: center;
    margin-bottom: 8px;
    letter-spacing: 0.05em;
  }
  .login-input {
    width: 100%;
    padding: 12px 10px;
    border-radius: 8px;
    border: none;
    background: #232526;
    color: #f5f5f5;
    font-size: 1rem;
    margin-bottom: 4px;
    outline: none;
    transition: background 0.2s;
  }
  .login-input:focus {
    background: #2a2c2e;
  }
  .login-btn {
    width: 100%;
    padding: 12px 0;
    border-radius: 8px;
    border: none;
    background: linear-gradient(90deg,#3a3d40,#232526);
    color: #fff;
    font-size: 1.1rem;
    font-weight: bold;
    cursor: pointer;
    margin-top: 8px;
    transition: background 0.2s;
  }
  .login-btn:active {
    background: #232526;
  }
  .login-error {
    color: #ff5a5a;
    font-size: 0.95rem;
    text-align: center;
    margin-top: 4px;
  }
  .dark-toggle {
    display: flex;
    justify-content: flex-end;
    margin-bottom: 8px;
  }
  .dark-toggle input {
    accent-color: #3a3d40;
  }
</style>

<div class="login-container">
  <div class="dark-toggle">
    <label style="font-size:0.95rem">
      <input type="checkbox" bind:checked={$dark} on:change={() => {
        document.body.style.setProperty('--bg', $dark ? '#181a1b' : '#f5f5f5');
        document.body.style.setProperty('--fg', $dark ? '#f5f5f5' : '#181a1b');
      }} /> 다크모드
    </label>
  </div>
  <div class="login-title">Risuai 로그인</div>
  <input class="login-input" type="text" placeholder="아이디" bind:value={username} autocomplete="username" />
  <input class="login-input" type="password" placeholder="비밀번호" bind:value={password} autocomplete="current-password" />
  <input class="login-input" type="text" placeholder="OTP 코드" bind:value={otp} autocomplete="one-time-code" />
  <button class="login-btn" on:click={login} disabled={loading}>{loading ? '로그인 중...' : '로그인'}</button>
  {#if error}
    <div class="login-error">{error}</div>
  {/if}
</div>
