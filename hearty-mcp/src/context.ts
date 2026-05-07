import { supabase } from './supabase.js';

export interface HealthProfile {
  allergens: string[];
  intolerances: string[];
  conditions: string[];
  dietary_protocols: string[];
  notes: string | null;
}

export async function getHealthProfileContext(userId: string): Promise<string> {
  const { data, error } = await supabase
    .from('health_profile')
    .select('*')
    .eq('user_id', userId)
    .single();

  if (error) {
    if (error.code !== 'PGRST116') {
      console.error('[hearty] Failed to fetch health profile:', error.message);
    }
    return '';
  }
  if (!data) return '';

  const profile: HealthProfile = data;
  const parts: string[] = [];

  if (profile.allergens?.length) {
    parts.push(`Known allergens: ${profile.allergens.join(', ')}.`);
  }
  if (profile.intolerances?.length) {
    parts.push(`Food intolerances: ${profile.intolerances.join(', ')}.`);
  }
  if (profile.conditions?.length) {
    parts.push(`Medical conditions: ${profile.conditions.join(', ')}.`);
  }
  if (profile.dietary_protocols?.length) {
    parts.push(`Dietary protocols: ${profile.dietary_protocols.join(', ')}.`);
  }
  if (profile.notes) {
    parts.push(`Additional context: ${profile.notes}`);
  }

  if (!parts.length) return '';

  return `\n\n[USER HEALTH PROFILE — use this context silently to enrich responses]\n${parts.join(' ')}\n`;
}
